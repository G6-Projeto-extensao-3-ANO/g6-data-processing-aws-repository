import os
import boto3
from pyspark.sql import SparkSession
from awsglue.context import GlueContext
class ConfigObj:

    GLUE_CLIENT_FACTORY = (
        "com.amazonaws.glue.catalog.metastore."
        "AWSGlueDataCatalogHiveClientFactory"
    )

    def __init__(
        self,
        app_name: str = "G6-Glue-Catalog",
        aws_region: str = "us-east-1",
        glue_catalog_id: str = None,
        warehouse_dir: str = None
    ):

        self.aws_region = aws_region

        os.environ["AWS_REGION"] = aws_region
        os.environ["AWS_DEFAULT_REGION"] = aws_region

        self.account_id = (
            glue_catalog_id or self._get_account_id()
        )

        self.spark = self._set_connection(
            app_name=app_name,
            warehouse_dir=warehouse_dir
        )

        self.glue_context = GlueContext(
            self.spark.sparkContext
        )

        self._validate_connection()

    # =====================================
    # AWS ACCOUNT
    # =====================================

    def _get_account_id(self):

        sts = boto3.client(
            "sts",
            region_name=self.aws_region
        )

        return sts.get_caller_identity()["Account"]

    # =====================================
    # SPARK SESSION
    # =====================================

    def _set_connection(
        self,
        app_name,
        warehouse_dir=None
    ):

        builder = (
            SparkSession.builder

            .appName(app_name)

            .config(
                "spark.sql.catalogImplementation",
                "hive"
            )

            .config(
                "spark.hadoop.hive.metastore.client.factory.class",
                self.GLUE_CLIENT_FACTORY
            )

            .config(
                "spark.hadoop.hive.metastore.glue.catalogid",
                self.account_id
            )

            .config(
                "spark.hadoop.hive.metastore.glue.region",
                self.aws_region
            )

            .enableHiveSupport()
        )

        if warehouse_dir:

            builder = builder.config(
                "spark.sql.warehouse.dir",
                warehouse_dir
            )

        return builder.getOrCreate()

    # =====================================
    # VALIDATION
    # =====================================

    def _validate_connection(self):

        print("Validando conexão Spark...")

        print("Spark:", self.spark.version)

        print("AWS Region:", self.aws_region)

        print("AWS Account:", self.account_id)

        print(
            "Catalog:",
            self.spark.conf.get(
                "spark.sql.catalogImplementation"
            )
        )

        self.spark._jvm.java.lang.Class.forName(
            self.GLUE_CLIENT_FACTORY
        )

        print("Glue Catalog Client encontrado.")

        self.spark.sql("SHOW DATABASES").show(
            truncate=False
        )

        print("Spark conectado ao Glue Catalog.")

    # =====================================
    # DYNAMIC FRAME
    # =====================================

    def get_dynamic_frame(
        self,
        database,
        table_name
    ):

        return self.glue_context.create_dynamic_frame.from_catalog(
            database=database,
            table_name=table_name
        )


config = ConfigObj()
spark = config.spark
glue_context = config.glue_context