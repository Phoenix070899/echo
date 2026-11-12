# A review sent to a settled Worker could not be reported

Found: 2026-10-31
Where: crates/hub/src/daemon.rs (review_worker, done)
Fixed in: this change

The human's review from Echo was typed into a Worker that had already sent its Final Report; the Worker addressed it, but its `echoctl done` failed with "already settled", so the Orchestrator never heard the result.
Cause: typing into a Worker left its state settled, and `done` takes a report only from a live Worker.
Fix: work typed into a settled Worker (a review, or `echoctl worker task`) sets it running before the text goes in, and the idle check waits a full stretch after it.
Lesson: anything that gives a Worker more work must put it back in a state that accepts its report before the work reaches it; a first fix that waited for the screen to move lost the race to a fast Worker.
