# Human Conversation Intelligence (research of 15 Nov 2026)

The owner's research package "DODDY — Human Conversation Intelligence" (15 Nov 2026, Polish), as far as the work needs it in the repository:

- `01_Executive_Findings.md`: the summary and the decision order (report 01).
- `evaluation_scenarios.jsonl`: the 120 test specifications (60 base, 60 harder; 60 PL, 60 EN), all `specified_not_executed` in the package; `EVALUATION_SCENARIOS_README.md` says how to use them. Reference answers are for the grader, never input to the agent.
- `dialogue_examples.json`: the 60 written example dialogues the specifications point to (authored examples, not recordings or transcripts).
- `coverage.json`: which specifications became executable tests on 15 Nov 2026 (ElevenLabs text tests on the live main agent, Swift unit tests in DoddyCore), which need real audio, timing or a device, and which could still become text tests.

The other reports (02 to 13, the evidence matrix, the prompt modules A to H) stay in the owner's ZIP. What was applied from them, and what was deliberately left alone, is in decision `docs/decisions/2026-11-15-conversation-core-and-corrections.md`.

None of these files is a measurement of Doddy. The package's own words: "Scenariusze to projekty testów, nie wykonane pomiary i nie rzeczywiste transkrypcje."
