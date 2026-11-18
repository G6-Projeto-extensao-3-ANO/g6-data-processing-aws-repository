import sys
from pathlib import Path

APP_PATH = Path("/home/ubuntu/app")

if str(APP_PATH) not in sys.path:
    sys.path.insert(0, str(APP_PATH))

from config import config, spark

print(f"Spark inicializado: {spark.version}")
print(f"AWS Account: {config.account_id}")