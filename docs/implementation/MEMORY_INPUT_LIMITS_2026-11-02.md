# Saved-data input limits: release candidate

## Scope

Select commit `0380e63ec76acd775898ef56bfa6615cb7847a6c` from draft #169, without its messaging-server migration, quotas, external actions or provider changes. The notes snapshot and Messages snapshot reject lists over their existing limits before zod parses individual items. Both retain the `invalid_request` failure contract and do not write data on refusal.

## Evidence and policies

DOD-08 and DOD-09: a refused request reports that nothing was stored. DOD-11: error messages name the field but do not echo user content. Tests include poison items proving an over-limit list is rejected before an item is read, plus boundary-size successful writes and HTTP 400 responses. Full backend type-check and test results and current merge state are recorded on the pull request; this file does not claim a deployment or live-provider validation.

## Boundaries

This is a candidate until merged and tested. No service setting, migration or provider is changed. Render auto-deploy is off; deploying the backend is a separate action. The application code does not call this new guard until the backend is separately deployed.
