# Code-forward audit

Line-shape heuristic; a block counts as code-forward when >=60% of its lines match the code/config patterns. Re-run `scripts/audit_code_forward.py` after any corpus edit.

| file | declared target | measured | code-forward / total | status |
| --- | ---: | ---: | ---: | --- |
| 10-java | 40% | 94% | 65/69 | ok |
| 11-spring | 40% | 98% | 58/59 | ok |
| 12-postgresql | 40% | 92% | 55/60 | ok |
| 13-kafka | 35% | 86% | 42/49 | ok |
| 14-http-api | 15% | 18% | 8/45 | ok |
| 15-typescript | 45% | 98% | 41/42 | ok |
| 16-vue | 40% | 100% | 42/42 | ok |
| 17-tanstack | 35% | 100% | 38/38 | ok |
| 18-testing | 25% | 70% | 28/40 | ok |
| 19-architecture | 20% | 0% | 0/46 | ok |
| 20-observability | 25% | 80% | 24/30 | ok |
| 21-linux-infra | 45% | 92% | 37/40 | ok |
| 22-python | 40% | 97% | 28/29 | ok |
