from pyspark.sql import SparkSession
from awsglue.dynamic_frame import DynamicFrame
from awsglue.context import GlueContext


class Connection:

    def __init__(self, spark: SparkSession):
        self.spark = spark
        self.glue_context = GlueContext(spark.sparkContext)

    def _spark_sql_query(
        self,
        sql: str,
        database: str
    ):
        self.spark.catalog.setCurrentDatabase(database)

        return self.spark.sql(sql)

    def _sink_dnf_catalog(
        self,
        table: str,
        database: str,
        partition_cols: dict,
        dnf: DynamicFrame
    ):
        return self.glue_context.write_dynamic_frame.from_catalog(
            frame=dnf,
            database=database,
            table_name=table,
            additional_options={
                "partitionKeys": list(partition_cols.keys())
            }
        )

    def _repair_partitions(
        self,
        table: str,
        database: str
    ):
        return self._spark_sql_query(
            sql=f"MSCK REPAIR TABLE `{database}`.`{table}`",
            database=database
        )