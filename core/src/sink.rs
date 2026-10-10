//! The event-reporting command sink (spec §5.3).

use std::{
    borrow::Cow,
    future::{Future, ready},
    pin::pin,
    sync::{
        PoisonError, RwLock, RwLockReadGuard, TryLockError,
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
    /// Called after every command with the event it caused or its error. A
    /// reset that doesn't say whether to keep the attempt's times may be
    /// waiting for it, so it must return promptly and not wait on other
    /// commands.
    fn report(&self, result: Result);
    /// Called when a reset doesn't say whether to keep the attempt's times and
    /// the attempt has new best times. Blocks the calling thread until the
    /// user answers. The timer is not locked while it waits.
    fn decide_reset(&self) -> ResetDecision;
    /// Called by every reset that doesn't say whether to keep the attempt's
    /// times, after other commands start getting Busy and just before it waits
    /// for the commands already running to finish. A seam for the tests.
    #[cfg(test)]
    fn waiting_for_commands(&self) {}
}

/// Wraps the shared timer, applies every command to it and reports the result
/// to the host, as LiveSplit One's `LSOCommandSink` does.
pub struct EventSink<H: Host> {
    timer: SharedTimer,
    host: H,
    /// Set from the moment a reset that doesn't say whether to keep the
    /// attempt's times starts until its result has been reported, whether or
    /// not it asks. Commands arriving meanwhile get Busy.
    exclusive_reset: AtomicBool,
    /// Held shared by each running command until its result has been
    /// reported, and exclusively by a reset that doesn't say whether to keep
    /// the attempt's times, from before it reads whether the attempt has new
    /// best times until its result has been reported. So such a reset waits
    /// for the commands already running, and none runs from then until it has
    /// reported, including while it asks. Unrelated to the timer's own lock,
    /// which is not held while the host decides.
    gate: RwLock<()>,
}

impl<H: Host> EventSink<H> {
    /// Creates a sink for a handle to the shared timer.
    pub fn new(timer: SharedTimer, host: H) -> Self {
        Self {
            timer,
            host,
            exclusive_reset: AtomicBool::new(false),
            gate: RwLock::new(()),
        }
    }

    /// Runs a command against the shared timer and reports the result, or
    /// reports Busy without waiting while a reset that doesn't say whether to
    /// keep the attempt's times is running.
    fn apply(&self, command: impl FnOnce(&SharedTimer) -> Result) -> Result {
        let running = match self.gate.try_read() {
            Ok(guard) => Some(guard),
            // Only a reset whose host panicked poisons the gate, and that
            // reset is over.
            Err(TryLockError::Poisoned(poisoned)) => Some(poisoned.into_inner()),
            Err(TryLockError::WouldBlock) => None,
        }
        // Checked while holding the gate: a reset that sets the flag after
        // this waits for the command to finish.
        .filter(|_| !self.exclusive_reset.load(Ordering::Acquire));
        let result = match running {
            Some(_) => command(&self.timer),
            None => Err(Error::Busy),
        };
        self.host.report(result);
        drop(running);
        result
    }

    /// Resets without being told whether to keep the attempt's times. Every
    /// such reset makes other commands Busy until it has reported, whether or
    /// not it asks. It first waits for the commands already running to finish
    /// and be reported, then holds the gate; only then, if the attempt has new
    /// best times, does it ask the host. It applies the answer and reports the
    /// result before releasing the gate, so no other command can slip in
    /// between.
    fn reset_unless_told(&self) -> Result {
        if self.exclusive_reset.swap(true, Ordering::AcqRel) {
            self.host.report(Err(Error::Busy));
            return Err(Error::Busy);
        }
        // Clears the flag even if the host panics.
        struct Clear<'a>(&'a AtomicBool);
        impl Drop for Clear<'_> {
            fn drop(&mut self) {
                self.0.store(false, Ordering::Release);
            }
        }
        let _clear = Clear(&self.exclusive_reset);
        #[cfg(test)]
        self.host.waiting_for_commands();
        // Waits for the commands already running. Dropped before `_clear`.
        let _exclusive = self.gate.write().unwrap_or_else(PoisonError::into_inner);

        let has_new_best_times = self
            .timer
            .read()
            .unwrap()
            .current_attempt_has_new_best_times();
        let save = if has_new_best_times {
            match self.host.decide_reset() {
                ResetDecision::Save => Ok(true),
                ResetDecision::Discard => Ok(false),
                ResetDecision::Cancel => Err(Error::RunnerDecidedAgainstReset),
            }
        } else {
            Ok(true)
        };
        let result = save.and_then(|save| now(CommandSink::reset(&self.timer, Some(save))));
        self.host.report(result);
        result
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
        ready(match save_attempt {
            Some(save) => self.apply(|t| now(CommandSink::reset(t, Some(save)))),
            None => self.reset_unless_told(),
        })
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

    /// Waits on a channel, failing instead of hanging if a change breaks the
    /// path that should send. A safety net, not for ordering.
    pub(crate) fn wait<T>(rx: &mpsc::Receiver<T>, what: &str) -> T {
        rx.recv_timeout(std::time::Duration::from_secs(10))
            .unwrap_or_else(|_| panic!("timed out after 10 s waiting for {what}"))
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
            wait(&self.answer.lock().unwrap(), "the answer")
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
        wait(&asked_rx, "the reset question");

        assert_eq!(run(sink.split()), Err(Error::Busy));
        assert_eq!(run(sink.reset(None)), Err(Error::Busy));
        // Drawing still gets the read lock while the question is open.
        assert_eq!(sink.get_timer().current_split_index(), Some(1));

        answer_tx.send(ResetDecision::Save).unwrap();
        assert_eq!(resetting.join().unwrap(), Ok(Event::Reset));
        assert_eq!(run(sink.start()), Ok(Event::Started));
    }

    /// A host that, while a reset question is open and while the decided
    /// reset is reported, issues commands from other threads and records what
    /// they got.
    struct Probing {
        sink: Mutex<Option<Arc<EventSink<Probing>>>>,
        during: Mutex<Vec<Result>>,
        reported: Mutex<Vec<Result>>,
        after_answer: Mutex<Vec<Result>>,
    }

    impl Host for Probing {
        fn report(&self, result: Result) {
            self.reported.lock().unwrap().push(result);
            if result == Ok(Event::Reset) {
                // The decided reset has been applied; it still makes other
                // commands Busy until this returns.
                let sink = self.sink.lock().unwrap().clone().unwrap();
                let other = std::thread::spawn(move || run(sink.split()))
                    .join()
                    .unwrap();
                self.after_answer.lock().unwrap().push(other);
            }
        }
        fn decide_reset(&self) -> ResetDecision {
            let sink = self.sink.lock().unwrap().clone().unwrap();
            let others = std::thread::spawn(move || [run(sink.split()), run(sink.reset(None))])
                .join()
                .unwrap();
            self.during.lock().unwrap().extend(others);
            ResetDecision::Save
        }
    }

    #[test]
    fn no_command_slips_in_between_the_answer_and_the_reset() {
        let sink = Arc::new(EventSink::new(
            timer(&["One", "Two"]),
            Probing {
                sink: Mutex::new(None),
                during: Mutex::default(),
                reported: Mutex::default(),
                after_answer: Mutex::default(),
            },
        ));
        *sink.host.sink.lock().unwrap() = Some(sink.clone());
        run(sink.start()).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(2));
        run(sink.split()).unwrap();
        sink.host.reported.lock().unwrap().clear();

        assert_eq!(run(sink.reset(None)), Ok(Event::Reset));
        assert_eq!(
            *sink.host.during.lock().unwrap(),
            [Err(Error::Busy), Err(Error::Busy)]
        );
        // Still Busy once the answer has been applied, until the reset is done.
        assert_eq!(*sink.host.after_answer.lock().unwrap(), [Err(Error::Busy)]);
        // Every outcome is reported exactly once (the last probe's Busy comes
        // while the reset is being reported).
        assert_eq!(
            *sink.host.reported.lock().unwrap(),
            [
                Err(Error::Busy),
                Err(Error::Busy),
                Ok(Event::Reset),
                Err(Error::Busy)
            ]
        );
        assert_eq!(sink.get_timer().run().attempt_history().len(), 1);
        *sink.host.sink.lock().unwrap() = None; // Breaks the reference cycle.
    }

    /// A host whose report of the next split waits until a reset that doesn't
    /// say whether to keep the attempt's times is waiting for it, or until the
    /// question is asked, and which records the order things happen in. Its
    /// probe deliberately covers the moment before the reset takes the write
    /// lock; a command arriving while the writer is queued gets Busy through
    /// `try_read`'s WouldBlock or the flag, which isn't tested separately.
    struct InFlight {
        sink: Mutex<Option<Arc<EventSink<InFlight>>>>,
        armed: Mutex<bool>,
        in_report: Mutex<mpsc::Sender<()>>,
        release_tx: Mutex<mpsc::Sender<()>>,
        release_rx: Mutex<mpsc::Receiver<()>>,
        log: Mutex<Vec<&'static str>>,
        while_waiting: Mutex<Vec<Result>>,
    }

    impl Host for InFlight {
        fn report(&self, result: Result) {
            if result == Ok(Event::Splitted) && std::mem::take(&mut *self.armed.lock().unwrap()) {
                self.in_report.lock().unwrap().send(()).unwrap();
                wait(&self.release_rx.lock().unwrap(), "the split to be released");
                self.log.lock().unwrap().push("split reported");
            }
        }
        fn decide_reset(&self) -> ResetDecision {
            self.log.lock().unwrap().push("asked");
            // Lets a split still being reported finish, if the reset didn't
            // wait for it.
            self.release_tx.lock().unwrap().send(()).unwrap();
            ResetDecision::Save
        }
        fn waiting_for_commands(&self) {
            // A command arriving now gets Busy without waiting.
            let sink = self.sink.lock().unwrap().clone().unwrap();
            let other = std::thread::spawn(move || run(sink.split()))
                .join()
                .unwrap();
            self.while_waiting.lock().unwrap().push(other);
            self.release_tx.lock().unwrap().send(()).unwrap();
        }
    }

    #[test]
    fn a_reset_waits_for_commands_already_running_before_asking() {
        let (in_report_tx, in_report_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let sink = Arc::new(EventSink::new(
            timer(&["One", "Two", "Three"]),
            InFlight {
                sink: Mutex::new(None),
                armed: Mutex::new(false),
                in_report: Mutex::new(in_report_tx),
                release_tx: Mutex::new(release_tx),
                release_rx: Mutex::new(release_rx),
                log: Mutex::default(),
                while_waiting: Mutex::default(),
            },
        ));
        *sink.host.sink.lock().unwrap() = Some(sink.clone());
        run(sink.start()).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(2));
        run(sink.split()).unwrap();
        *sink.host.armed.lock().unwrap() = true;

        // A split passes the check and is still being reported...
        let splitting = {
            let sink = sink.clone();
            std::thread::spawn(move || run(sink.split()))
        };
        wait(&in_report_rx, "the split to be reported");
        // ...when a reset that doesn't say whether to keep the attempt's times
        // arrives.
        let resetting = {
            let sink = sink.clone();
            std::thread::spawn(move || run(sink.reset(None)))
        };

        assert_eq!(resetting.join().unwrap(), Ok(Event::Reset));
        assert_eq!(splitting.join().unwrap(), Ok(Event::Splitted));
        assert_eq!(*sink.host.log.lock().unwrap(), ["split reported", "asked"]);
        assert_eq!(*sink.host.while_waiting.lock().unwrap(), [Err(Error::Busy)]);
        *sink.host.sink.lock().unwrap() = None; // Breaks the reference cycle.
    }

    /// A host whose first reset question panics.
    #[derive(Default)]
    struct Panicking {
        asked: Mutex<u32>,
    }

    impl Host for Panicking {
        fn report(&self, _: Result) {}
        fn decide_reset(&self) -> ResetDecision {
            let mut asked = self.asked.lock().unwrap();
            *asked += 1;
            if *asked == 1 {
                drop(asked);
                panic!("the host panicked");
            }
            ResetDecision::Save
        }
    }

    #[test]
    fn the_sink_still_works_after_the_host_panics_during_a_question() {
        let sink = Arc::new(EventSink::new(
            timer(&["One", "Two", "Three"]),
            Panicking::default(),
        ));
        run(sink.start()).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(2));
        run(sink.split()).unwrap();

        let panicked = {
            let sink = sink.clone();
            std::thread::spawn(move || run(sink.reset(None)))
        };
        assert!(panicked.join().is_err());
        assert!(sink.gate.is_poisoned());

        assert_eq!(run(sink.split()), Ok(Event::Splitted));
        assert_eq!(run(sink.reset(None)), Ok(Event::Reset));
        assert_eq!(*sink.host.asked.lock().unwrap(), 2);
    }

    /// A host whose report of the next pause waits until a reset is waiting
    /// for it, or until a reset has been reported, which records the order
    /// things happen in, and which fails if it is asked about a reset.
    struct NotAsking {
        sink: Mutex<Option<Arc<EventSink<NotAsking>>>>,
        armed: Mutex<bool>,
        in_report: Mutex<mpsc::Sender<()>>,
        release_tx: Mutex<mpsc::Sender<()>>,
        release_rx: Mutex<mpsc::Receiver<()>>,
        log: Mutex<Vec<&'static str>>,
        while_resetting: Mutex<Vec<Result>>,
    }

    impl Host for NotAsking {
        fn report(&self, result: Result) {
            if result == Ok(Event::Paused) && std::mem::take(&mut *self.armed.lock().unwrap()) {
                self.in_report.lock().unwrap().send(()).unwrap();
                wait(&self.release_rx.lock().unwrap(), "the pause to be released");
                self.log.lock().unwrap().push("pause reported");
            } else if result == Ok(Event::Reset) {
                self.log.lock().unwrap().push("reset reported");
                // The reset still holds the gate: a command arriving now gets
                // Busy.
                let sink = self.sink.lock().unwrap().clone().unwrap();
                let other = std::thread::spawn(move || run(sink.split()))
                    .join()
                    .unwrap();
                self.while_resetting.lock().unwrap().push(other);
                // Lets a pause still being reported finish, if the reset
                // didn't wait for it.
                self.release_tx.lock().unwrap().send(()).unwrap();
            }
        }
        fn decide_reset(&self) -> ResetDecision {
            panic!("asked about a reset without new best times");
        }
        fn waiting_for_commands(&self) {
            self.release_tx.lock().unwrap().send(()).unwrap();
        }
    }

    #[test]
    fn a_reset_that_does_not_ask_still_waits_for_commands_and_makes_others_busy() {
        let (in_report_tx, in_report_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let sink = Arc::new(EventSink::new(
            timer(&["One", "Two"]),
            NotAsking {
                sink: Mutex::new(None),
                armed: Mutex::new(false),
                in_report: Mutex::new(in_report_tx),
                release_tx: Mutex::new(release_tx),
                release_rx: Mutex::new(release_rx),
                log: Mutex::default(),
                while_resetting: Mutex::default(),
            },
        ));
        *sink.host.sink.lock().unwrap() = Some(sink.clone());
        run(sink.start()).unwrap();
        assert!(!sink.get_timer().current_attempt_has_new_best_times());
        *sink.host.armed.lock().unwrap() = true;

        // A pause passes the check and is still being reported...
        let pausing = {
            let sink = sink.clone();
            std::thread::spawn(move || run(sink.pause()))
        };
        wait(&in_report_rx, "the pause to be reported");
        // ...when a reset that doesn't say whether to keep the attempt's times
        // arrives. There are no new best times, so it doesn't ask.
        let resetting = {
            let sink = sink.clone();
            std::thread::spawn(move || run(sink.reset(None)))
        };

        assert_eq!(resetting.join().unwrap(), Ok(Event::Reset));
        assert_eq!(pausing.join().unwrap(), Ok(Event::Paused));
        assert_eq!(
            *sink.host.log.lock().unwrap(),
            ["pause reported", "reset reported"]
        );
        assert_eq!(
            *sink.host.while_resetting.lock().unwrap(),
            [Err(Error::Busy)]
        );
        *sink.host.sink.lock().unwrap() = None; // Breaks the reference cycle.
    }
}
