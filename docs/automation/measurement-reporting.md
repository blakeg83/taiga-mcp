# Measurement reporting

Reports show raw usage and the exact role/model/effort profile first. Raw
processing counters are not a price and are not a subscription allowance.

Actual monetary or subscription consumption is `unknown` unless the supplied
source attributes it to this run. An API estimate is optional and requires
dated model-specific input, cached-input, and output rates plus a rate source.
Reasoning is counted inside output only when the source contract says it is;
the report records that assumption. An API estimate is never applied to a
ChatGPT allowance.

No report automatically changes model, effort, or a token ceiling. A Luna run
using more raw tokens can still be the better result when quality, time, and
available cost evidence support it.
