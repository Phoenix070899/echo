# A phone paired again after a new pairing link got no notifications, while its Settings said On

Found: 2026-10-26
Where: crates/hub/remote/index.html (pair, restorePush), crates/hub/src/remote.rs (new_pairing)
Fixed in: the change that adds this file

After New Pairing Link, a phone that had notifications on paired again and Echo Remote's Settings still read "On", but no push arrived and the daemon counted 0 phones with notifications.
Cause: a new pairing link clears every phone's subscription on the daemon (features/0028), while the browser keeps its own; pairing never handed it back, and Settings asks only the browser.
Fix: on pairing, the page posts the browser's existing push subscription to `/api/push/subscribe` again, and the toast says notifications are still on.
Lesson: when the daemon forgets state the browser also holds, restore it from the browser at the step that brings the two back together, so they cannot disagree silently.
