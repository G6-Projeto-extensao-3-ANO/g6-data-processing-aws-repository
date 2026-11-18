
from awsglue.dynamicframe import DynamicFrame
from datetime import datetime
import json


class Padronization:

    def __init__(self, glue_context):
        self.glue_context = glue_context

    def _normalize_str(
        self,
        dnf: DynamicFrame,
        column: str
    ) -> DynamicFrame:

        def normalize(record):
            value = record.get(column)

            if isinstance(value, str):
                record[column] = value.strip()

            return record

        return dnf.map(f=normalize)

    def _normalize_int(
        self,
        dnf: DynamicFrame,
        column: str
    ) -> DynamicFrame:

        def normalize(record):
            value = record.get(column)

            if value is not None:
                try:
                    record[column] = int(value)
                except (ValueError, TypeError):
                    record[column] = None

            return record

        return dnf.map(f=normalize)

    def _normalize_datetime(
        self,
        dnf: DynamicFrame,
        column: str,
        input_format: str = "%Y-%m-%d %H:%M:%S",
        output_format: str = "%Y-%m-%d %H:%M:%S"
    ) -> DynamicFrame:

        def normalize(record):
            value = record.get(column)

            if value is not None:
                try:
                    if isinstance(value, datetime):
                        parsed = value
                    else:
                        parsed = datetime.strptime(
                            str(value).strip(),
                            input_format
                        )

                    record[column] = parsed.strftime(output_format)

                except (ValueError, TypeError):
                    record[column] = None

            return record

        return dnf.map(f=normalize)

    def _deserialize_dict(
        self,
        dnf: DynamicFrame,
        column: str
    ) -> DynamicFrame:

        def deserialize(record):
            value = record.get(column)

            if isinstance(value, str):
                try:
                    record[column] = json.loads(value)
                except (json.JSONDecodeError, TypeError):
                    record[column] = None

            return record

        return dnf.map(f=deserialize)