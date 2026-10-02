//! Who caused a request (`actor`), stamped by the owner of the connection,
//! never by the caller (plans/cmux-next/OWNERSHIP-PRINCIPLES.md).
//!
//! - A control connection's requests act as `user`, or `agent:<id>` once
//!   the connection is bound to an agent's conversation token.
//! - The app supervisor stamps `app:<id>` on every call it routes for an app.
//!
//! Callers cannot send an `actor` field: the protocol-v2 envelope denies
//! unknown fields. The stamp travels as a scope around one request's
//! dispatch on the dispatching thread (the dispatch is synchronous, the
//! pattern `event_bus::defer_session_paths` uses), and the owner writes it
//! into the replay record of each mutation it commits (the `origin` column of
//! `resource_mutations` and the resource journal record).

use std::cell::RefCell;
use std::fmt;

/// The replay-record origin of protocol-v2 mutations dispatched with no
/// actor scope (in-process tests; records written before actors existed).
pub(crate) const UNSCOPED_ORIGIN: &str = "resource-api";

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Actor {
    User,
    App(String),
    Agent(String),
}

impl fmt::Display for Actor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::User => f.write_str("user"),
            Self::App(id) => write!(f, "app:{id}"),
            Self::Agent(id) => write!(f, "agent:{id}"),
        }
    }
}

impl Actor {
    /// The actor of a control connection.
    pub(crate) fn of_client(mux: &crate::Mux, client: u64) -> Self {
        let principal = mux.conversation_principal(client);
        if principal == crate::conversation_store::LOCAL_USER {
            Self::User
        } else {
            Self::Agent(principal)
        }
    }
}

thread_local! {
    static CURRENT: RefCell<Option<Actor>> = const { RefCell::new(None) };
}

/// Runs `f` with `actor` as the stamp of every mutation it commits on this
/// thread; the previous stamp comes back afterwards, also on panic.
pub(crate) fn scoped<R>(actor: Actor, f: impl FnOnce() -> R) -> R {
    struct Restore(Option<Actor>);
    impl Drop for Restore {
        fn drop(&mut self) {
            let previous = self.0.take();
            CURRENT.with(|cell| *cell.borrow_mut() = previous);
        }
    }
    let previous = CURRENT.with(|cell| cell.borrow_mut().replace(actor));
    let _restore = Restore(previous);
    f()
}

/// The stamp of the request being dispatched on this thread, if any.
pub(crate) fn current() -> Option<Actor> {
    CURRENT.with(|cell| cell.borrow().clone())
}

/// The replay-record origin for a protocol-v2 mutation dispatched now.
pub(crate) fn mutation_origin() -> String {
    current().map_or_else(|| UNSCOPED_ORIGIN.to_string(), |actor| actor.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scopes_nest_restore_and_print_the_wire_form() {
        assert_eq!(mutation_origin(), UNSCOPED_ORIGIN);
        scoped(Actor::User, || {
            assert_eq!(mutation_origin(), "user");
            scoped(Actor::App("cmux/demo".into()), || assert_eq!(mutation_origin(), "app:cmux/demo"));
            assert_eq!(mutation_origin(), "user");
        });
        let _ = std::panic::catch_unwind(|| scoped(Actor::Agent("a1".into()), || panic!("boom")));
        assert_eq!(current(), None, "a panic restores the previous stamp");
    }
}

#[cfg(test)]
#[path = "actor_tests.rs"]
mod actor_tests;
