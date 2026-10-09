//! LiveSplit One's server protocol on native (spec §5.3). livesplit-core's C
//! API only exposes it on the web (`capi/src/lib.rs`, `server_protocol`).

use livesplit_core::{event::Event, networking::server_protocol};

use crate::sink::{EventSink, Host};

/// Runs one server protocol message against the sink and returns the reply to
/// send back. The sink's futures are ready at once, so this never waits,
/// except for a reset decision (see [`Host::decide_reset`]).
pub fn handle_command<H: Host>(sink: &EventSink<H>, command: &str) -> String {
    futures_executor::block_on(server_protocol::handle_command(command, sink))
}

/// Encodes an event, given as livesplit-core's number for it, as LiveSplit One
/// sends it to the server. Unknown numbers encode as `"Unknown"`, as in
/// LiveSplit One (`capi/src/server_protocol.rs`).
pub fn encode_event(event: u32) -> String {
    server_protocol::encode_event(Event::from(event))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sink::{
        ResetDecision,
        tests::{Recorder, timer},
    };
    use std::sync::Arc;

    fn sink() -> (EventSink<Arc<Recorder>>, Arc<Recorder>) {
        let recorder = Arc::new(Recorder::default());
        (
            EventSink::new(timer(&["One", "Two"]), recorder.clone()),
            recorder,
        )
    }

    #[test]
    fn a_command_succeeds_and_reports_its_event() {
        let (sink, recorder) = sink();
        assert_eq!(
            handle_command(&sink, r#"{"command":"splitOrStart"}"#),
            r#"{"success":null}"#
        );
        assert_eq!(*recorder.results.lock().unwrap(), [Ok(Event::Started)]);
    }

    #[test]
    fn a_rejected_command_replies_with_the_timer_error() {
        let (sink, _) = sink();
        assert_eq!(
            handle_command(&sink, r#"{"command":"split"}"#),
            r#"{"error":{"code":"NoRunInProgress"}}"#
        );
    }

    #[test]
    fn invalid_json_replies_invalid_command() {
        let (sink, recorder) = sink();
        let reply = handle_command(&sink, "not json");
        assert!(
            reply.starts_with(r#"{"error":{"code":"InvalidCommand","message":"#),
            "{reply}"
        );
        assert!(recorder.results.lock().unwrap().is_empty());
    }

    #[test]
    fn queries_read_the_timer() {
        let (sink, _) = sink();
        handle_command(&sink, r#"{"command":"start"}"#);
        assert_eq!(
            handle_command(&sink, r#"{"command":"getCurrentState"}"#),
            r#"{"success":{"state":"Running","index":0}}"#
        );
    }

    #[test]
    fn game_time_commands_work() {
        let (sink, recorder) = sink();
        handle_command(&sink, r#"{"command":"start"}"#);
        handle_command(&sink, r#"{"command":"initializeGameTime"}"#);
        assert_eq!(
            handle_command(&sink, r#"{"command":"setGameTime","time":"1:23.5"}"#),
            r#"{"success":null}"#
        );
        assert_eq!(
            recorder.results.lock().unwrap().last(),
            Some(&Ok(Event::GameTimeSet))
        );
    }

    #[test]
    fn a_server_reset_waits_for_the_decision_and_replies_with_it() {
        let (sink, recorder) = sink();
        handle_command(&sink, r#"{"command":"start"}"#);
        std::thread::sleep(std::time::Duration::from_millis(2));
        handle_command(&sink, r#"{"command":"split"}"#);
        *recorder.decision.lock().unwrap() = Some(ResetDecision::Cancel);
        assert_eq!(
            handle_command(&sink, r#"{"command":"reset"}"#),
            r#"{"error":{"code":"RunnerDecidedAgainstReset"}}"#
        );
        assert_eq!(
            handle_command(&sink, r#"{"command":"reset","saveAttempt":false}"#),
            r#"{"success":null}"#
        );
        assert_eq!(*recorder.asked.lock().unwrap(), 1);
    }

    #[test]
    fn encodes_events_as_livesplit_one_does() {
        assert_eq!(
            encode_event(Event::Splitted as u32),
            r#"{"event":"Splitted"}"#
        );
        assert_eq!(encode_event(Event::Reset as u32), r#"{"event":"Reset"}"#);
        assert_eq!(encode_event(9999), r#"{"event":"Unknown"}"#);
    }
}
