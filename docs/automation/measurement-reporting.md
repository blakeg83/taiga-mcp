# Measurement reporting

Reports show raw usage and the exact role/model/effort profile first. Raw
processing counters are not a price and are not a subscription allowance.

Actual monetary or subscription consumption is `unknown` unless the supplied
source attributes it to this run. An API estimate is optional and requires
dated model-specific input, cached-input, and output rates plus a rate source.
Reasoning is counted inside output only when the source contract says it is;
the report records that assumption. An API estimate is never applied to a
ChatGPT allowance.

Usage snapshots must include a stable stream ID, with an explicit legacy
single-stream adapter for unambiguous old exports. Exact start-boundary samples
are baselines; intervals straddling the start without one remain unknown.
Missing baselines and counter resets remain unknown, and later samples are
reported but not attributed to the run.
Long timing runs use the append-only audit stream after recent-registry
eviction and correlate dispatch/observation/receipt events by action and worker
when possible.

Healthy recovery ticks should be measured as compact `wait` observations. Their
footprint is limited to worker status, wait state, cursors, and the native wait
descriptor; source, ticket rereads, diff review, and test reruns are excluded.
Record any residual token/usage counters with an explicit stream and run
boundary. If the source cannot attribute them to the heartbeat, report the
residual cost as unknown rather than converting raw tokens into a subscription
or monetary claim.

No report automatically changes model, effort, or a token ceiling. A Luna run
using more raw tokens can still be the better result when quality, time, and
available cost evidence support it.
