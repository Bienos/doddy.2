Known Ubuntu-only CI helpers and workflows skip the Mac jobs. Changes to app inputs and shared CI scripts still run them.
Mac CI removes the extra project listing and stops on failed package resolution. CI logs now show elapsed time per step.
Ubuntu setup reuses dependencies already installed on the runner. See the decision `2026-11-18-ios-ci-fast-feedback`.
