
import os
from pathlib import Path

import boto3
from pyspark.sql import SparkSession


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
        glue_catalog_jars: list[str] = None,
        warehouse_dir: str = None
    ):
        self.aws_region = aws_region

        os.environ["AWS_REGION"] = aws_region

        self.account_id = (
            glue_catalog_id or self._get_account_id()
        )

        self.glue_catalog_jars = self._resolve_jars(
            glue_catalog_jars
        )

        self.spark = self._set_connection(
            app_name=app_name,
            warehouse_dir=warehouse_dir
        )

        self._validate_connection()

    def _get_account_id(self) -> str:

        sts = boto3.client(
            "sts",
            region_name=self.aws_region
        )

        return sts.get_caller_identity()["Account"]

    def _resolve_jars(
        self,
        jars: list[str] = None
    ) -> list[str]:

        if jars is None:
            jars_env = os.getenv("GLUE_CATALOG_JARS", "")

            jars = [
                path.strip()
                for path in jars_env.split(",")
                if path.strip()
            ]

        if not jars:
            raise RuntimeError(
                "JARs do AWS Glue Data Catalog Client não encontrados. "
                "Configure GLUE_CATALOG_JARS."
            )

        resolved = []

        for jar in jars:

            path = Path(jar).expanduser().resolve()

            if not path.is_file():
                raise FileNotFoundError(
                    f"JAR não encontrado: {path}"
                )

            if path.suffix.lower() != ".jar":
                raise ValueError(
                    f"Arquivo inválido, esperado JAR: {path}"
                )

            resolved.append(str(path))

        return resolved

    def _set_connection(
        self,
        app_name: str,
        warehouse_dir: str = None
    ) -> SparkSession:

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
                    "spark.jars",
                    ",".join(self.glue_catalog_jars)
                )

                .enableHiveSupport()
        )

        if warehouse_dir:
            builder = builder.config(
                "spark.sql.warehouse.dir",
                warehouse_dir
            )

        return builder.getOrCreate()

    def _validate_connection(self):

        print("Validando conexão Spark...")

        print(f"Spark: {self.spark.version}")
        print(f"AWS Region: {self.aws_region}")
        print(f"AWS Account: {self.account_id}")

        implementation = self.spark.conf.get(
            "spark.sql.catalogImplementation"
        )

        if implementation.lower() != "hive":
            raise RuntimeError(
                "Spark não está utilizando Hive Catalog."
            )

        try:
            self.spark._jvm.java.lang.Class.forName(
                self.GLUE_CLIENT_FACTORY
            )

        except Exception as error:
            raise RuntimeError(
                "Cliente AWS Glue não encontrado no classpath "
                "do Spark. Verifique os JARs instalados."
            ) from error

        print("Cliente Glue encontrado no classpath.")
        print("Spark inicializado com sucesso.")

config = ConfigObj()
spark = config.spark