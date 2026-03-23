1s

1s

1s

2s

14s

1s

11s

0s

5s

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:1)Run pytest --cov=app --cov-report=xml:coverage.xml --cov-fail-under=70 -q tests --ignore=tests/test_hardware_integration.py

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:15)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:16)ERROR: Coverage failure: total of 2 is less than fail-under=70

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:17)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:18)==================================== ERRORS ====================================

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:19)____________________ ERROR collecting tests/test_config.py _____________________

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:20)app/config.py:199: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:21)settings.jwt_secret = generate_jwt_secret()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:22)app/config.py:23: in generate_jwt_secret

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:23)secret_file.parent.mkdir(parents=True, exist_ok=True)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:24)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/pathlib.py:1311: in mkdir

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:25)os.mkdir(self, mode)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:26)E PermissionError: [Errno 13] Permission denied: '/var/lib/aihomecloud'

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:27)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:28)During handling of the above exception, another exception occurred:

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:29)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/runner.py:341: in from_call

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:30)result: Optional[TResult] = func()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:31)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/runner.py:372: in <lambda>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:32)call = CallInfo.from_call(lambda: list(collector.collect()), "collect")

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:33)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/pytest_asyncio/plugin.py:644: in _patched_collect

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:34)module = collector.obj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:35)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:310: in obj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:36)self._obj = obj = self._getobj()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:37)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:528: in _getobj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:38)return self._importtestmodule()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:39)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:617: in _importtestmodule

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:40)mod = import_path(self.path, mode=importmode, root=self.config.rootpath)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:41)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/pathlib.py:565: in import_path

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:42)importlib.import_module(module_name)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:43)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/importlib/__init__.py:90: in import_module

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:44)return _bootstrap._gcd_import(name[level:], package, level)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:45)<frozen importlib._bootstrap>:1387: in _gcd_import

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:46)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:47)<frozen importlib._bootstrap>:1360: in _find_and_load

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:48)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:49)<frozen importlib._bootstrap>:1331: in _find_and_load_unlocked

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:50)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:51)<frozen importlib._bootstrap>:935: in _load_unlocked

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:52)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:53)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/assertion/rewrite.py:178: in exec_module

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:54)exec(co, module.__dict__)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:55)tests/test_config.py:3: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:56)from app.config import generate_jwt_secret

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:57)app/config.py:206: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:58)raise SystemExit(1)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:59)E SystemExit: 1

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:60)________________ ERROR collecting tests/test_document_index.py _________________

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:61)app/config.py:199: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:62)settings.jwt_secret = generate_jwt_secret()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:63)app/config.py:23: in generate_jwt_secret

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:64)secret_file.parent.mkdir(parents=True, exist_ok=True)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:65)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/pathlib.py:1311: in mkdir

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:66)os.mkdir(self, mode)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:67)E PermissionError: [Errno 13] Permission denied: '/var/lib/aihomecloud'

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:68)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:69)During handling of the above exception, another exception occurred:

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:70)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/runner.py:341: in from_call

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:71)result: Optional[TResult] = func()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:72)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/runner.py:372: in <lambda>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:73)call = CallInfo.from_call(lambda: list(collector.collect()), "collect")

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:74)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/pytest_asyncio/plugin.py:644: in _patched_collect

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:75)module = collector.obj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:76)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:310: in obj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:77)self._obj = obj = self._getobj()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:78)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:528: in _getobj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:79)return self._importtestmodule()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:80)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:617: in _importtestmodule

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:81)mod = import_path(self.path, mode=importmode, root=self.config.rootpath)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:82)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/pathlib.py:565: in import_path

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:83)importlib.import_module(module_name)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:84)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/importlib/__init__.py:90: in import_module

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:85)return _bootstrap._gcd_import(name[level:], package, level)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:86)<frozen importlib._bootstrap>:1387: in _gcd_import

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:87)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:88)<frozen importlib._bootstrap>:1360: in _find_and_load

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:89)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:90)<frozen importlib._bootstrap>:1331: in _find_and_load_unlocked

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:91)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:92)<frozen importlib._bootstrap>:935: in _load_unlocked

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:93)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:94)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/assertion/rewrite.py:178: in exec_module

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:95)exec(co, module.__dict__)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:96)tests/test_document_index.py:10: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:97)from app.config import settings

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:98)app/config.py:206: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:99)raise SystemExit(1)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:100)E SystemExit: 1

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:101)____________________ ERROR collecting tests/test_hygiene.py ____________________

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:102)app/config.py:199: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:103)settings.jwt_secret = generate_jwt_secret()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:104)app/config.py:23: in generate_jwt_secret

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:105)secret_file.parent.mkdir(parents=True, exist_ok=True)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:106)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/pathlib.py:1311: in mkdir

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:107)os.mkdir(self, mode)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:108)E PermissionError: [Errno 13] Permission denied: '/var/lib/aihomecloud'

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:109)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:110)During handling of the above exception, another exception occurred:

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:111)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/runner.py:341: in from_call

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:112)result: Optional[TResult] = func()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:113)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/runner.py:372: in <lambda>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:114)call = CallInfo.from_call(lambda: list(collector.collect()), "collect")

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:115)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/pytest_asyncio/plugin.py:644: in _patched_collect

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:116)module = collector.obj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:117)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:310: in obj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:118)self._obj = obj = self._getobj()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:119)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:528: in _getobj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:120)return self._importtestmodule()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:121)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:617: in _importtestmodule

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:122)mod = import_path(self.path, mode=importmode, root=self.config.rootpath)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:123)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/pathlib.py:565: in import_path

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:124)importlib.import_module(module_name)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:125)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/importlib/__init__.py:90: in import_module

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:126)return _bootstrap._gcd_import(name[level:], package, level)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:127)<frozen importlib._bootstrap>:1387: in _gcd_import

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:128)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:129)<frozen importlib._bootstrap>:1360: in _find_and_load

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:130)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:131)<frozen importlib._bootstrap>:1331: in _find_and_load_unlocked

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:132)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:133)<frozen importlib._bootstrap>:935: in _load_unlocked

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:134)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:135)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/assertion/rewrite.py:178: in exec_module

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:136)exec(co, module.__dict__)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:137)tests/test_hygiene.py:3: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:138)from app.config import settings

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:139)app/config.py:206: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:140)raise SystemExit(1)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:141)E SystemExit: 1

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:142)_________________ ERROR collecting tests/test_index_watcher.py _________________

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:143)app/config.py:199: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:144)settings.jwt_secret = generate_jwt_secret()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:145)app/config.py:23: in generate_jwt_secret

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:146)secret_file.parent.mkdir(parents=True, exist_ok=True)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:147)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/pathlib.py:1311: in mkdir

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:148)os.mkdir(self, mode)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:149)E PermissionError: [Errno 13] Permission denied: '/var/lib/aihomecloud'

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:150)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:151)During handling of the above exception, another exception occurred:

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:152)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/runner.py:341: in from_call

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:153)result: Optional[TResult] = func()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:154)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/runner.py:372: in <lambda>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:155)call = CallInfo.from_call(lambda: list(collector.collect()), "collect")

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:156)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/pytest_asyncio/plugin.py:644: in _patched_collect

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:157)module = collector.obj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:158)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:310: in obj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:159)self._obj = obj = self._getobj()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:160)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:528: in _getobj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:161)return self._importtestmodule()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:162)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:617: in _importtestmodule

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:163)mod = import_path(self.path, mode=importmode, root=self.config.rootpath)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:164)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/pathlib.py:565: in import_path

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:165)importlib.import_module(module_name)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:166)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/importlib/__init__.py:90: in import_module

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:167)return _bootstrap._gcd_import(name[level:], package, level)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:168)<frozen importlib._bootstrap>:1387: in _gcd_import

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:169)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:170)<frozen importlib._bootstrap>:1360: in _find_and_load

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:171)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:172)<frozen importlib._bootstrap>:1331: in _find_and_load_unlocked

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:173)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:174)<frozen importlib._bootstrap>:935: in _load_unlocked

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:175)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:176)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/assertion/rewrite.py:178: in exec_module

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:177)exec(co, module.__dict__)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:178)tests/test_index_watcher.py:5: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:179)from app.config import settings

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:180)app/config.py:206: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:181)raise SystemExit(1)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:182)E SystemExit: 1

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:183)_________________ ERROR collecting tests/test_telegram_bot.py __________________

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:184)app/config.py:199: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:185)settings.jwt_secret = generate_jwt_secret()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:186)app/config.py:23: in generate_jwt_secret

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:187)secret_file.parent.mkdir(parents=True, exist_ok=True)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:188)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/pathlib.py:1311: in mkdir

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:189)os.mkdir(self, mode)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:190)E PermissionError: [Errno 13] Permission denied: '/var/lib/aihomecloud'

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:191)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:192)During handling of the above exception, another exception occurred:

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:193)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/runner.py:341: in from_call

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:194)result: Optional[TResult] = func()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:195)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/runner.py:372: in <lambda>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:196)call = CallInfo.from_call(lambda: list(collector.collect()), "collect")

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:197)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/pytest_asyncio/plugin.py:644: in _patched_collect

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:198)module = collector.obj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:199)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:310: in obj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:200)self._obj = obj = self._getobj()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:201)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:528: in _getobj

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:202)return self._importtestmodule()

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:203)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/python.py:617: in _importtestmodule

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:204)mod = import_path(self.path, mode=importmode, root=self.config.rootpath)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:205)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/pathlib.py:565: in import_path

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:206)importlib.import_module(module_name)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:207)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/importlib/__init__.py:90: in import_module

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:208)return _bootstrap._gcd_import(name[level:], package, level)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:209)<frozen importlib._bootstrap>:1387: in _gcd_import

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:210)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:211)<frozen importlib._bootstrap>:1360: in _find_and_load

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:212)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:213)<frozen importlib._bootstrap>:1331: in _find_and_load_unlocked

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:214)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:215)<frozen importlib._bootstrap>:935: in _load_unlocked

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:216)???

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:217)/opt/hostedtoolcache/Python/3.12.13/x64/lib/python3.12/site-packages/_pytest/assertion/rewrite.py:178: in exec_module

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:218)exec(co, module.__dict__)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:219)tests/test_telegram_bot.py:17: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:220)from app.config import settings

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:221)app/config.py:206: in <module>

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:222)raise SystemExit(1)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:223)E SystemExit: 1

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:224)================================ tests coverage ================================

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:225)_______________ coverage: platform linux, python 3.12.13-final-0 _______________

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:226)

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:227)Coverage XML written to file coverage.xml

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:228)FAIL Required test coverage of 70% not reached. Total coverage: 2.00%

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:229)=========================== short test summary info ============================

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:230)ERROR tests/test_config.py - SystemExit: 1

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:231)ERROR tests/test_document_index.py - SystemExit: 1

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:232)ERROR tests/test_hygiene.py - SystemExit: 1

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:233)ERROR tests/test_index_watcher.py - SystemExit: 1

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:234)ERROR tests/test_telegram_bot.py - SystemExit: 1

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:235)!!!!!!!!!!!!!!!!!!! Interrupted: 5 errors during collection !!!!!!!!!!!!!!!!!!!!

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:236)5 errors in 3.50s

[](https://github.com/nerdyparas/AiHomeCloud/actions/runs/23157157419/job/67274840030#step:9:237)Error: Process completed with exit code 2.

2s

0s

0s

0s

0s




