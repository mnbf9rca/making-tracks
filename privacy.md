# Privacy Policy — Making Tracks

Making Tracks is a privacy-focused travel app. Where possible, it keeps your data on your device. Where it can't, it tells you plainly what is happening.

This privacy policy governs how we design and build the app. If a feature can't be built inside the principles of this policy, the feature changes.

## Core principles

1. Your saved activity stays on your device. Nothing you save leaves unless you choose to share it.
2. Accounts are not required to use the app unless you choose to. For example, sharing a list privately requires an account, but using the app for yourself does not.
3. No analytics SDKs. No advertising identifiers. No third-party trackers.
4. We never sell your data or give it to another company. (Sharing a list, below, is you choosing to send one list to people you pick.)
5. Everything beyond the basic app is off until you turn it on, one feature at a time.
6. We do not track where users are. The app builds a trail of where you've been, but that trail is private to you.
7. Every feature takes only the data it needs to work.
8. Where something can see you, we say so. We never call a thing "anonymous" when it isn't.
9. The app is open source. You can read exactly what it does: https://github.com/mnbf9rca/making-tracks

## What we collect about you

Your visits, saves, and lists live in a database on your phone, and that database never leaves your phone except if you share a list (see below).

If you hit a problem, you can choose to send a diagnostic log to someone helping you — usually us, when you ask for help. That file records what you did in the app and how it responded during a short window you pick, so the problem can be understood. Nothing is collected or sent automatically: you choose when to share it and who to send it to, and the screen shows you what it contains first. It does not include your device's name, your exact location, or the words you typed into search.

## Backups and device sync

If you use Apple's iCloud device backup, your backup includes this data just like your other apps, but we cannot see it.

When we add sync, it uses Apple's iCloud under your Apple account. The contents stay private to you. We cannot see them.

## How we minimise data collection when you use our services

Data about places is created by our servers for everyone, and packaged in to "bundles" which cover a small geographic area. Your phone downloads bundles to use the app. A bundle contains:
- a map of the area
- the places in that area, including their names, descriptions, and photos
- other data about the area or the places.

When your phone talks to our servers (hosted on Cloudflare) — to download a bundle, or to stream the map in the meantime — this is what happens:

- Cloudflare sees your device's internet (IP) address and the time, like any website you visit. This is not anonymous but we don't log it. Cloudflare may log it.
- A bundle covers a geographical area, which could be part of a city or town, whole city or country. Just because you download a bundle, it doesn't mean you've visited that area.
- We have no way to keep any records of which person or device downloaded or fetched what.
- We do count how many **times** each **bundle** is downloaded, to see which areas need more work. We can't tell who downloaded which one.

We recognise that this can still leak some information. For example, it's theoretically possible to track which devices are visiting which areas, but this is very hard - users get different IP addresses, and we don't send any identifier with the request. But in future we will make bundles even smaller so that an area can be downloaded in smaller pieces. You will be able to choose to tell the app to hide which one you actually want — for example by quietly fetching a few others at the same time. We're still working out how, and we don't have it yet.

## Sharing lists, reporting problems, and optional usage statistics

### Sharing a list

You can share a list as either *private* (only people you invite) or a *public* link. You can choose whether others can view, add (but not remove), or fully edit.

- Only the list you share leaves your phone, only to the people you choose (named individuals or a public link).
- Your list does NOT say whether you've visited any of the places, or what you loved. It only contains the places themselves, and any notes you added to the list.
- Your other lists, your visits, and your map history stay on your phone.
- Sharing *public* lists does not require an account, but if you do not use an account and you uninstall the app on your phone, you may not be able to edit or delete the list after you share it. This is because we would have no way to know it was *your* list.

### Creating an account

Because private sharing needs to identify you and your recipients, we offer an account system. You can create an account with your email address or Apple ID. We do not require an account to use the app for yourself:

- It will store: the way to identify you for sharing, and the lists you chose to share.
- It will **not** store: your visits, your map, your history, or anything you didn't share.
- It is never used to track what you do. You never need it to use the app for yourself.

### Reporting a problem with a place

You can flag problems with a place (gone, wrong, and so on).

- A report contains nothing about you. We can't tell who sent one. The report comes to our servers over the internet which means Cloudflare can see your IP, but we do not link it back to you or your device.
- They are advisory only, reviewed by a person before anything changes on the map.
- One person or script can't change the map. It takes multiple independent reports and a human.

### Optional place statistics

The app may offer to let you share when you saved or loved a place. This is optional, but helps good places surface.

- Off unless you turn it on. Offered once, in plain language.
- No identifiers. Dates only, never times.
- Events sent separately at random delays. The statistics come to our servers over the internet which means Cloudflare can see your IP, but we do not link it back to you or your device.
- A count (e.g. "10 people love this place") is only shown in the app once enough people share it that no one stands out.
- We'll keep looking for ways to make this even harder to trace back to you.

## Where place information comes from

Places, descriptions, and photos come from open data. We credit every source — see [attribution.md](attribution.md). We treat all of it as untrusted: checked, size-limited, and shown as plain text, so a bad entry in a public database can't harm your phone.

## Checking this is true

The app is open source: https://github.com/mnbf9rca/making-tracks. Read the code and confirm the
rules above are how it's built. You don't have to take our word for it.
