# Evidence-Driven Synchronization

Use this reference whenever production code, test support, fixtures, tests, validation tooling, or pressure workflows introduce or change asynchronous completion, delays, sleeps, timers, polling, retry schedules, deadlines, timeouts, expiration, animation timing, or elapsed-duration requirements.

## Shared Contract

- Drive progress from observable evidence: callbacks, notifications, readbacks, generations, explicit state transitions, process state, window identity, or an independent Oracle.
- Reject fixed-delay temporal coupling, including raw sleeps, fixed RunLoop settling, delayed actions that assume prior work completed, and elapsed-time windows used as readiness, success, or correctness signals.
- Treat a watchdog as a terminal failure bound. Keep the observable condition as the sole success signal and report the last observed evidence when the watchdog expires.
- Own every wait, observer, timer, retry, and watchdog from the lifecycle object that starts it. Preserve cancellation through every suspension and check it before post-wait side effects or shared task-state mutation.
- Centralize and name remaining duration policies. Inject a clock or scheduler when elapsed time is part of the domain rule so deterministic tests can advance it explicitly.
- Require machine speed, scheduling pressure, I/O latency, and animation load to affect completion latency only; they must not change the result.

## Production Rules

- Consume the platform callback or publish a readiness state when an asynchronous API already exposes completion.
- Establish a baseline snapshot and observe a later generation or state transition when startup, launch, permission, AX, CG, projection, or window topology must converge.
- Use concrete activation evidence for window workflows: the selected CGWindowID must become onscreen through a retained activation route and verified readback.
- Use condition polling only when work must observe or advance convergence and no callback, notification, generation, or other event source exposes the required transition. Encapsulate it in the resource-owning boundary, document why no event source is available, check the observable condition immediately before waiting, and keep that condition or readback as the sole success signal.
- Keep polling cadence in a named, cancellable policy owned by the lifecycle object. Stop on success or cancellation and use a watchdog with the last observed evidence as the terminal failure bound. When polling performs a recovery action, trigger every attempt from observed failure or incomplete evidence, keep retry timing inside a named resilience policy, and determine the final outcome from readback evidence.
- Propagate `CancellationError` or explicitly return after cancellation. Do not swallow a canceled sleep and continue into refreshes, permission checks, state transitions, logging, or task-slot cleanup.
- Use elapsed duration directly only when time is the product contract, such as a user-selected delay, animation, expiration, or sustained pressure exposure. Keep the duration explicit, owned, configurable where appropriate, and clock-injectable.

## Test And Fixture Rules

- Complete tests from their independent Oracle by awaiting expectations, callbacks, notifications, actor or model state, projection generations, process state, log markers, accessibility state, or exact window evidence.
- Replace raw `Thread.sleep`, `Task.sleep`, fixed `RunLoop` advances, and settle delays used as readiness or success signals with deterministic handshakes or condition observation. When no usable event source exists, a condition observer may use a named, cancellable polling cadence; it must check immediately and derive success only from its predicate or readback, while its timeout remains a watchdog.
- Inject clocks, schedulers, and retry drivers into unit and behavior tests; advance them explicitly without wall-clock waiting.
- Make fixtures publish readiness and transition acknowledgements. Let UI tests wait for those signals or for the user-visible state they cause.
- Provide watchdogs through shared test infrastructure with diagnostics that identify the unmet condition and last observation. Treat XCTest and UI wait timeouts as watchdogs only.
- Define pressure completion by the required workload, sample count, stability evidence, or explicit sustained-duration contract. Record the duration as measurement protocol evidence when elapsed exposure is itself required.

## Review Checklist

Before accepting asynchronous production or test logic, answer all of the following:

1. What observable evidence defines readiness or success?
2. Which callback, notification, generation, state transition, or readback exposes that evidence, or why is no event source available?
3. If polling remains, is its cadence named and cancellable, and is every recovery action triggered by observed failure or incomplete evidence?
4. Who owns cancellation and lifecycle cleanup?
5. Is every remaining duration a domain rule or terminal watchdog with a named owner?
6. Can deterministic tests drive the clock, scheduler, retry, and completion path?
7. Can a slower or busier machine change latency without changing the result?
