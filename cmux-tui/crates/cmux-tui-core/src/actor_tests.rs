//! The owner records the dispatching actor in each mutation's replay record,
//! and a caller cannot supply one.

use serde_json::{Value, json};

use super::{Actor, UNSCOPED_ORIGIN, scoped};
use crate::{Mux, SurfaceOptions};

fn create(mux: &std::sync::Arc<Mux>, key: &str) -> Value {
    let request = json!({
        "protocol": "cmux.protocol/2", "type": "request", "id": key,
        "operation": "workspace.create", "idempotency_key": key,
        "params": { "machine": "current", "session": "current", "name": key, "initial_content": "empty" },
    });
    crate::resource_router::handle_resource_message(mux, &request.to_string()).expect("dispatch")
}

/// `origin` of the replay record for `key`, read from the session database.
fn recorded_origin(mux: &Mux, key: &str) -> String {
    let dir = mux.session_state_directory().expect("persistent session");
    for entry in std::fs::read_dir(&dir).expect("state dir") {
        let path = entry.expect("entry").path();
        let Ok(db) = rusqlite::Connection::open_with_flags(&path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
        else {
            continue;
        };
        let found = db.query_row(
            "SELECT origin FROM resource_mutations WHERE idempotency_key = ?1",
            [key],
            |row| row.get::<_, String>(0),
        );
        if let Ok(origin) = found {
            return origin;
        }
    }
    panic!("no replay record for {key} in {}", dir.display());
}

#[test]
fn replay_records_carry_the_dispatching_actor() {
    let root = std::env::temp_dir().join(format!("cmux-actor-{}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    let mux = Mux::open_persistent("actor", SurfaceOptions::default(), &root).unwrap();
    let app = scoped(Actor::App("cmux/demo".into()), || create(&mux, "by-app"));
    assert_eq!(app["ok"], true, "{app}");
    scoped(Actor::User, || create(&mux, "by-user"));
    scoped(Actor::Agent("agent_7".into()), || create(&mux, "by-agent"));
    create(&mux, "unscoped");
    assert_eq!(recorded_origin(&mux, "by-app"), "app:cmux/demo");
    assert_eq!(recorded_origin(&mux, "by-user"), "user");
    assert_eq!(recorded_origin(&mux, "by-agent"), "agent:agent_7");
    assert_eq!(recorded_origin(&mux, "unscoped"), UNSCOPED_ORIGIN);
    // A replay under another actor answers the stored result and keeps the first stamp.
    let replay = scoped(Actor::User, || create(&mux, "by-app"));
    assert_eq!(replay["result"]["replayed"], true, "{replay}");
    assert_eq!(recorded_origin(&mux, "by-app"), "app:cmux/demo");
    drop(mux);
    std::fs::remove_dir_all(&root).ok();
}

#[test]
fn a_caller_cannot_send_an_actor() {
    let request = json!({
        "protocol": "cmux.protocol/2", "type": "request", "id": "x",
        "operation": "workspace.list", "actor": "user",
        "params": { "machine": "current", "session": "current" },
    });
    let error = crate::resource_router::parse_resource_request(&request.to_string())
        .err()
        .expect("an envelope with actor is refused");
    assert_eq!(error.code, "validation.invalid");
    let mut without = request;
    without.as_object_mut().unwrap().remove("actor");
    assert!(crate::resource_router::parse_resource_request(&without.to_string()).is_ok());
}
