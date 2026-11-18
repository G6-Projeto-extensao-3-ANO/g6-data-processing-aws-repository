from pyspark.sql import SparkSession
from awsglue.dynamic_frame import DynamicFrame
from awsglue.context import GlueContext


class Connection:

    def __init__(
        self,
        spark: SparkSession,
        glue_context: GlueContext
    ):
        self.spark = spark
        self.glue_context = glue_context

    def _spark_sql_query(
        self,
        sql: str,
        database: str,
        mapping: dict[str, DynamicFrame]
    ):
        self.spark.catalog.setCurrentDatabase(database)

        for name, dnf in mapping.items():
            dnf.toDF().createOrReplaceTempView(name)
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
            database=database,
            mapping={}
        )

    def create_dynamicframe_from_catalog(
        self,
        ymd: str,
        database: str,
        table: str,
    ) -> DynamicFrame:

        return self.glue_context.create_dynamic_frame.from_catalog(
            database=database,
            table_name=table,
            transformation_ctx=f"source_{table}",
            push_down_predicate=f"ymd = '{ymd}'"
        )