# Code-forward audit

Line-shape heuristic; a block counts as code-forward when >=60% of its lines match the code/config patterns. Re-run `scripts/audit_code_forward.py` after any corpus edit.

| file | declared target | measured | code-forward / total | status |
| --- | ---: | ---: | ---: | --- |
| 10-java | 40% | 98% | 62/63 | ok |
| 11-spring | 40% | 100% | 53/53 | ok |
| 12-postgresql | 40% | 96% | 52/54 | ok |
| 13-kafka | 35% | 95% | 42/44 | ok |
| 14-http-api | 15% | 12% | 5/41 | ok |
| 15-typescript | 45% | 97% | 36/37 | ok |
| 16-vue | 40% | 100% | 37/37 | ok |
| 17-tanstack | 35% | 100% | 33/33 | ok |
| 18-testing | 25% | 71% | 25/35 | ok |
| 19-architecture | 20% | 0% | 0/41 | ok |
| 20-observability | 25% | 88% | 23/26 | ok |
| 21-linux-infra | 45% | 97% | 34/35 | ok |
| 22-python | 40% | 100% | 25/25 | ok |
