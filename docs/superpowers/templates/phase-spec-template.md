# Phase &lt;n&gt; Spec — &lt;title&gt;

Date: YYYY-MM-DD. Status: draft → ratified in-session by Rob. **A ratified spec is immutable for the phase; changing it means another design session.**
Adversarial gate: codex-r runs one XHIGH attack on this draft before ratification (spec §5). Drafted live by opus.

## 1. Goal

&lt;Narrative of what this phase delivers.&gt;

## 2. Non-goals

&lt;Explicit out-of-scope statements — what this phase deliberately does not do.&gt;

## 3. Acceptance criteria

Testable, **behaviour-level** statements of "done" — each gradable pass/fail by the acceptance pass. Vague criteria are rejected in-session.

- [ ] **AC1:** &lt;behaviour-level statement&gt;
- [ ] **AC2:** &lt;behaviour-level statement&gt;

## 4. Wireframes

For each user-facing surface: HTML source path, a rendered PNG at **390×844**, and an **accessibility-size variant**. Opus specifies the layout; a build agent authors the HTML and renders; opus validates; Rob rules in-session before ratification. **No new wireframes are authored mid-build — the build implements against ruled wireframes only.**

- Surface: &lt;name&gt; — source `docs/design/&lt;area&gt;/wf-&lt;name&gt;.html`; renders `&lt;name&gt;-default.png`, `&lt;name&gt;-ax.png`; ruled: &lt;yes / date&gt;.

## 5. Contracts

Cross-track interfaces fixed **before dependent tasks start** (PRINCIPLES.md Engineering 18).

- Contract: &lt;name&gt; — &lt;signature / data shape&gt;.

## 6. Judgment rules for this phase

The standing spirit rules apply (spec §6, fold-or-file). Record any phase-specific judgment calls here so the acceptance pass can grade against them.

- &lt;rule&gt;.
