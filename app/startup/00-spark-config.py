import sys
from pathlib import Path

APP_PATH = Path("/home/hadoop/app")

if str(APP_PATH) not in sys.path:
    sys.path.insert(0, str(APP_PATH))

from config import (
    config,
    spark,
    glue_context
)

print("=" * 50)
print("G6 - SPARK INITIALIZED")
print("Spark:", spark.version)
print("AWS Account:", config.account_id)
print("AWS Region:", config.aws_region)
print("GlueContext:", type(glue_context).__name__)
print("=" * 50)