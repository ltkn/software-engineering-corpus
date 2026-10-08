# Code-forward audit

Line-shape heuristic; a block counts as code-forward when >=60% of its lines match the code/config patterns. Re-run `scripts/audit_code_forward.py` after any corpus edit.

| file | declared target | measured | code-forward / total | status |
| --- | ---: | ---: | ---: | --- |
| 10-java | 40% | 94% | 72/77 | ok |
| 11-spring | 40% | 98% | 64/65 | ok |
| 12-postgresql | 40% | 90% | 61/68 | ok |
| 13-kafka | 35% | 82% | 42/51 | ok |
| 14-http-api | 15% | 18% | 10/57 | ok |
| 15-typescript | 45% | 96% | 52/54 | ok |
| 16-vue | 40% | 98% | 55/56 | ok |
| 17-tanstack | 35% | 100% | 52/52 | ok |
| 18-testing | 25% | 71% | 30/42 | ok |
| 19-architecture | 20% | 0% | 0/48 | ok |
| 20-observability | 25% | 80% | 24/30 | ok |
| 21-linux-infra | 45% | 90% | 38/42 | ok |
| 22-python | 40% | 97% | 28/29 | ok |
