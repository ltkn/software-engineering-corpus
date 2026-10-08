# Code-forward audit

Line-shape heuristic; a block counts as code-forward when >=60% of its lines match the code/config patterns. Re-run `scripts/audit_code_forward.py` after any corpus edit.

| file | declared target | measured | code-forward / total | status |
| --- | ---: | ---: | ---: | --- |
| 10-java | 40% | 94% | 75/80 | ok |
| 11-spring | 40% | 98% | 65/66 | ok |
| 12-postgresql | 40% | 87% | 62/71 | ok |
| 13-kafka | 35% | 82% | 42/51 | ok |
| 14-http-api | 15% | 18% | 10/57 | ok |
| 15-typescript | 45% | 96% | 54/56 | ok |
| 16-vue | 40% | 98% | 57/58 | ok |
| 17-tanstack | 35% | 100% | 53/53 | ok |
| 18-testing | 25% | 70% | 30/43 | ok |
| 19-architecture | 20% | 0% | 0/48 | ok |
| 20-observability | 25% | 81% | 25/31 | ok |
| 21-linux-infra | 45% | 87% | 39/45 | ok |
| 22-python | 40% | 91% | 31/34 | ok |
