//! The event-reporting command sink (spec §5.3).

use std::{
    borrow::Cow,
    future::{Future, ready},
    pin::pin,
    sync::{
        RwLockReadGuard,
        atomic::{AtomicBool, Ordering},
    },
    task::{Context, Poll, Waker},
};

use livesplit_core::{
    SharedTimer, TimeSpan, Timer, TimingMethod,
    event::{CommandSink, Error, Result, TimerQuery},
};

/// What the host decided when a reset needs a decision. The values match the
/// buttons of LiveSplit One's dialog: Yes, No, Don't Reset.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum ResetDecision {
    /// Keep the attempt's times (Yes).
    Save,
    /// Discard the attempt's times (No).
    Discard,
    /// Don't reset.
    Cancel,
}

/// The app side of the sink: told about every result, and asked about resets.
pub trait Host: Send + Sync + 'static {
    /// Called after every command with the event it caused or its error.
    fn report(&self, result: Result);
    /// Called when a reset doesn't say whether to keep the attempt's times and
    /// the attempt has new best times. Blocks the calling thread until the
    /// user answers. The timer is not locked while it waits.
    fn decide_reset(&self) -> ResetDecision;
}

/// Wraps the shared timer, applies every command to it and reports the result
/// to the host, as LiveSplit One's `LSOCommandSink` does.
pub struct EventSink<H: Host> {
    timer: SharedTimer,
    host: H,
    deciding: AtomicBool,
}

impl<H: Host> EventSink<H> {
    /// Creates a sink for a handle to the shared timer.
    pub fn new(timer: SharedTimer, host: H) -> Self {
        Self {
            timer,
            host,
            deciding: AtomicBool::new(false),
        }
    }

    /// Runs a command against the shared timer, unless a reset decision is
    /// pending, and reports the result.
    fn apply(&self, command: impl FnOnce(&SharedTimer) -> Result) -> Result {
        let result = if self.deciding.load(Ordering::Acquire) {
            Err(Error::Busy)
        } else {
            command(&self.timer)
        };
        self.host.report(result);
        result
    }

    fn reset_decision(&self) -> core::result::Result<bool, Error> {
        if self.deciding.swap(true, Ordering::AcqRel) {
            return Err(Error::Busy);
        }
        // Clears the flag even if the host panics.
        struct Clear<'a>(&'a AtomicBool);
        impl Drop for Clear<'_> {
            fn drop(&mut self) {
                self.0.store(false, Ordering::Release);
            }
        }
        let _clear = Clear(&self.deciding);

        let has_new_best_times = self
            .timer
            .read()
            .unwrap()
            .current_attempt_has_new_best_times();
        if !has_new_best_times {
            return Ok(true);
        }
        match self.host.decide_reset() {
            ResetDecision::Save => Ok(true),
            ResetDecision::Discard => Ok(false),
            ResetDecision::Cancel => Err(Error::RunnerDecidedAgainstReset),
        }
    }
}

/// Takes the result of one of `SharedTimer`'s command futures. They apply the
/// command when created and are ready at once (livesplit-core `src/event.rs`,
/// `impl CommandSink for SharedTimer`), so one poll is enough. This doesn't use
/// an executor, because `handle_command` already runs inside one, and
/// `futures_executor::block_on` panics when nested.
fn now(future: impl Future<Output = Result>) -> Result {
    let mut context = Context::from_waker(Waker::noop());
    match pin!(future).poll(&mut context) {
        Poll::Ready(result) => result,
        Poll::Pending => Err(Error::Unknown),
    }
}

impl<H: Host> CommandSink for EventSink<H> {
    fn start(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::start(t))))
    }
    fn split(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::split(t))))
    }
    fn split_or_start(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::split_or_start(t))))
    }
    fn reset(&self, save_attempt: Option<bool>) -> impl Future<Output = Result> + 'static {
        let result = match save_attempt {
            Some(save) => self.apply(|t| now(CommandSink::reset(t, Some(save)))),
            None => match self.reset_decision() {
                Ok(save) => self.apply(|t| now(CommandSink::reset(t, Some(save)))),
                Err(error) => {
                    self.host.report(Err(error));
                    Err(error)
                }
            },
        };
        ready(result)
    }
    fn undo_split(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::undo_split(t))))
    }
    fn skip_split(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::skip_split(t))))
    }
    fn toggle_pause_or_start(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::toggle_pause_or_start(t))))
    }
    fn pause(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::pause(t))))
    }
    fn resume(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::resume(t))))
    }
    fn undo_all_pauses(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::undo_all_pauses(t))))
    }
    fn switch_to_previous_comparison(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::switch_to_previous_comparison(t))))
    }
    fn switch_to_next_comparison(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::switch_to_next_comparison(t))))
    }
    fn set_current_comparison(
        &self,
        comparison: Cow<str>,
    ) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::set_current_comparison(t, comparison))))
    }
    fn toggle_timing_method(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::toggle_timing_method(t))))
    }
    fn set_current_timing_method(
        &self,
        method: TimingMethod,
    ) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::set_current_timing_method(t, method))))
    }
    fn initialize_game_time(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::initialize_game_time(t))))
    }
    fn set_game_time(&self, time: TimeSpan) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::set_game_time(t, time))))
    }
    fn pause_game_time(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::pause_game_time(t))))
    }
    fn resume_game_time(&self) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::resume_game_time(t))))
    }
    fn set_loading_times(&self, time: TimeSpan) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::set_loading_times(t, time))))
    }
    fn set_custom_variable(
        &self,
        name: Cow<str>,
        value: Cow<str>,
    ) -> impl Future<Output = Result> + 'static {
        ready(self.apply(|t| now(CommandSink::set_custom_variable(t, name, value))))
    }
}

impl<H: Host> TimerQuery for EventSink<H> {
    type Guard<'a> = RwLockReadGuard<'a, Timer>;
    fn get_timer(&self) -> Self::Guard<'_> {
        self.timer.read().unwrap()
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use livesplit_core::{Run, Segment, event::Event};
    use std::sync::{Arc, Mutex, mpsc};

    pub(crate) fn timer(segments: &[&str]) -> SharedTimer {
        let mut run = Run::new();
        for name in segments {
            run.push_segment(Segment::new(*name));
        }
        Timer::new(run).unwrap().into_shared()
    }

    #[derive(Default)]
    pub(crate) struct Recorder {
        pub results: Mutex<Vec<Result>>,
        pub decision: Mutex<Option<ResetDecision>>,
        pub asked: Mutex<u32>,
    }

    impl Host for Arc<Recorder> {
        fn report(&self, result: Result) {
            self.results.lock().unwrap().push(result);
        }
        fn decide_reset(&self) -> ResetDecision {
            *self.asked.lock().unwrap() += 1;
            self.decision
                .lock()
                .unwrap()
                .expect("unexpected reset question")
        }
    }

    fn sink(segments: &[&str]) -> (EventSink<Arc<Recorder>>, Arc<Recorder>) {
        let recorder = Arc::new(Recorder::default());
        (EventSink::new(timer(segments), recorder.clone()), recorder)
    }

    fn run<F: Future<Output = Result>>(future: F) -> Result {
        futures_executor::block_on(future)
    }

    #[test]
    fn applies_a_command_and_reports_its_event() {
        let (sink, recorder) = sink(&["One"]);
        assert_eq!(run(sink.start()), Ok(Event::Started));
        assert_eq!(*recorder.results.lock().unwrap(), [Ok(Event::Started)]);
        assert_eq!(
            sink.get_timer().current_phase(),
            livesplit_core::TimerPhase::Running
        );
    }

    #[test]
    fn reports_errors_too() {
        let (sink, recorder) = sink(&["One"]);
        assert_eq!(run(sink.split()), Err(Error::NoRunInProgress));
        assert_eq!(
            *recorder.results.lock().unwrap(),
            [Err(Error::NoRunInProgress)]
        );
    }

    #[test]
    fn reset_without_new_best_times_does_not_ask() {
        let (sink, recorder) = sink(&["One", "Two"]);
        run(sink.start()).unwrap();
        assert_eq!(run(sink.reset(None)), Ok(Event::Reset));
        assert_eq!(*recorder.asked.lock().unwrap(), 0);
    }

    fn with_new_best_segment(sink: &EventSink<Arc<Recorder>>) {
        run(sink.start()).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(2));
        run(sink.split()).unwrap();
        assert!(sink.get_timer().current_attempt_has_new_best_times());
    }

    #[test]
    fn reset_with_new_best_times_asks_and_saves() {
        let (sink, recorder) = sink(&["One", "Two"]);
        with_new_best_segment(&sink);
        *recorder.decision.lock().unwrap() = Some(ResetDecision::Save);
        assert_eq!(run(sink.reset(None)), Ok(Event::Reset));
        assert_eq!(*recorder.asked.lock().unwrap(), 1);
        assert_eq!(sink.get_timer().run().attempt_history().len(), 1);
        assert!(
            sink.get_timer()
                .run()
                .segment(0)
                .best_segment_time()
                .real_time
                .is_some()
        );
    }

    #[test]
    fn reset_with_new_best_times_can_discard() {
        let (sink, recorder) = sink(&["One", "Two"]);
        with_new_best_segment(&sink);
        *recorder.decision.lock().unwrap() = Some(ResetDecision::Discard);
        assert_eq!(run(sink.reset(None)), Ok(Event::Reset));
        assert!(
            sink.get_timer()
                .run()
                .segment(0)
                .best_segment_time()
                .real_time
                .is_none()
        );
    }

    #[test]
    fn reset_can_be_cancelled() {
        let (sink, recorder) = sink(&["One", "Two"]);
        with_new_best_segment(&sink);
        *recorder.decision.lock().unwrap() = Some(ResetDecision::Cancel);
        assert_eq!(run(sink.reset(None)), Err(Error::RunnerDecidedAgainstReset));
        assert_eq!(
            sink.get_timer().current_phase(),
            livesplit_core::TimerPhase::Running
        );
        assert_eq!(
            recorder.results.lock().unwrap().last(),
            Some(&Err(Error::RunnerDecidedAgainstReset))
        );
    }

    #[test]
    fn reset_that_says_whether_to_save_does_not_ask() {
        let (sink, recorder) = sink(&["One", "Two"]);
        with_new_best_segment(&sink);
        assert_eq!(run(sink.reset(Some(false))), Ok(Event::Reset));
        assert_eq!(*recorder.asked.lock().unwrap(), 0);
        assert!(
            sink.get_timer()
                .run()
                .segment(0)
                .best_segment_time()
                .real_time
                .is_none()
        );
    }

    /// A host whose reset question waits until the test lets it answer.
    struct Waiting {
        asked: mpsc::Sender<()>,
        answer: Mutex<mpsc::Receiver<ResetDecision>>,
    }

    impl Host for Waiting {
        fn report(&self, _: Result) {}
        fn decide_reset(&self) -> ResetDecision {
            self.asked.send(()).unwrap();
            self.answer.lock().unwrap().recv().unwrap()
        }
    }

    #[test]
    fn other_commands_are_busy_while_a_reset_waits_and_the_timer_is_not_locked() {
        let (asked_tx, asked_rx) = mpsc::channel();
        let (answer_tx, answer_rx) = mpsc::channel();
        let sink = Arc::new(EventSink::new(
            timer(&["One", "Two"]),
            Waiting {
                asked: asked_tx,
                answer: Mutex::new(answer_rx),
            },
        ));
        run(sink.start()).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(2));
        run(sink.split()).unwrap();

        let resetting = {
            let sink = sink.clone();
            std::thread::spawn(move || run(sink.reset(None)))
        };
        asked_rx.recv().unwrap();

        assert_eq!(run(sink.split()), Err(Error::Busy));
        assert_eq!(run(sink.reset(None)), Err(Error::Busy));
        // Drawing still gets the read lock while the question is open.
        assert_eq!(sink.get_timer().current_split_index(), Some(1));

        answer_tx.send(ResetDecision::Save).unwrap();
        assert_eq!(resetting.join().unwrap(), Ok(Event::Reset));
        assert_eq!(run(sink.start()), Ok(Event::Started));
    }
}
