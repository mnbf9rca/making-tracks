# Privacy Policy — Making Tracks

Making Tracks is a privacy-focused travel app. Where possible, it keeps your data on your device. Where it can't, it tells you plainly what is happening.

This privacy policy governs how we design and build the app. If a feature can't be built inside the principles of this policy, the feature changes.

## Core principles

These principles override everything.

- Your saved activity stays on your device. Nothing you save leaves unless you choose to share it.
- Accounts are not required to use the app unless you choose to. For example, sharing a list privately requires an account, but using the app for yourself does not.
- No analytics SDKs. No advertising identifiers. No third-party trackers.
- We never sell your data or give it to another company. (Sharing a list, below, is you choosing to send one list to people you pick.)
- Everything beyond the basic app is off until you turn it on, one feature at a time.
- We do not track where users are. The app builds a trail of where you've been, but that trail is private to you.
- Every feature takes only the data it needs to work.
- Where something can see you, we say so. We never call a thing "anonymous" when it isn't.
- The app is open source. You can read exactly what it does: https://github.com/mnbf9rca/making-tracks

## What we store about you

Right now, nothing. Your visits, saves, and lists live in a database on your phone. We have no copy. There is no account and no server that holds your activity.

If you use Apple's iCloud device backup, your backup includes this data, like your other apps'.
That is between you and Apple, under your Apple account. We never see it.

## How we minimise data collection when you use our services

To use the app you download a **bundle** — the map and the places for an area — onto your phone. After that, exploring that area needs nothing from us. (Until bundles ship, the app streams the map from our servers as you look around instead.)

When your phone talks to our servers (hosted on Cloudflare) — to download a bundle, or to stream the map in the meantime — this is what happens:

- Cloudflare sees your device's internet (IP) address and the time. Like any website you visit. This is not anonymous.
- A bundle covers a whole city or country. Downloading one says nothing about which places you go to. (While streaming, the app only ever asks for large areas, never your exact spot — so we still can't see which place you're looking at.)
- We keep no record of which person downloaded or fetched what.
- We do count how many times each bundle is downloaded, to see which areas need more work. We can't tell who downloaded which one.
- In future, when an area can be downloaded in smaller pieces, we plan to hide which one you actually want — for example by quietly fetching a few others at the same time. We're still working out how, and we don't have it yet.

## As the app grows

Each of these is opt-in and off until you use it. None of them changes the rules above.

**Sharing a list.** You'll be able to share a list — private (only people you invite) or a public link — and choose whether they can view, add (but not remove), or fully edit.

- Only the list you share leaves your phone, only to the people you choose.
- Your other lists, your visits, and your map history stay on your phone.
- Sharing *public* lists does not require an account, but if you do not use an account and you uninstall the app on your phone, you may not be able to edit or delete the list after you share it. This is because we would have no way to know it was *your* list.

**An account** (only because private sharing needs to identify you and your recipients):

- It will store: the way to identify you for sharing, and the lists you chose to share.
- It will not store: your visits, your map, your history, or anything you didn't share.
- It is never used to track what you do. You never need it to use the app for yourself.

**Reporting a problem with a place.** You'll be able to flag a place (gone, wrong, and so on).

- A report contains nothing about you. We can't tell who sent one — not even your internet address.
- They are advisory only, reviewed by a person before anything changes on the map.
- One person or script can't change the map. It takes multiple independent reports and a human.

**Optional usage statistics.** The app may offer to send aggregate counts (e.g. "some people saved this place") to help good places surface.

- Off unless you turn it on. Offered once, in plain language.
- No identifiers. Dates only, never times.
- Events sent separately at random delays, routed so even we never see your IP.
- A count is only reported once enough people share it that no one stands out.
- We'll keep looking for ways to make this even harder to trace back to you. We don't have those yet.

**Syncing across your devices.** When we add sync, it uses Apple's iCloud under your Apple account. The contents stay private to you. We never see them.

## Where place information comes from

Places, descriptions, and photos come from open data. We credit every source — see [attribution.md](attribution.md). We treat all of it as untrusted: checked, size-limited, and shown as plain text, so a bad entry in a public database can't harm your phone.

## Checking this is true

The app is open source: https://github.com/mnbf9rca/making-tracks. Read the code and confirm the
rules above are how it's built. You don't have to take our word for it.
