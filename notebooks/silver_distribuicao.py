# Databricks notebook source
# silver_distribuicao.py — Transformação da camada Silver para distribuição
# Este notebook é deployado via CI/CD pipeline para o workspace Databricks

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

def transform_distribuicao(spark, source_path, target_path):
    """Transforma dados brutos de distribuição (Bronze) para Silver."""
    df_bronze = spark.read.format("delta").load(source_path)

    df_silver = (
        df_bronze
        .filter(F.col("data_entrega").isNotNull())
        .withColumn(
            "lead_time_dias",
            F.datediff(F.col("data_entrega"), F.col("data_pedido")),
        )
        .withColumn("regiao", F.upper(F.col("regiao")))
        .dropDuplicates(["id_pedido"])
    )

    df_silver.write.format("delta").mode("overwrite").save(target_path)
    return df_silver.count()


if __name__ == "__main__":
    spark = SparkSession.builder.appName("silver_distribuicao").getOrCreate()
    count = transform_distribuicao(
        spark,
        "abfss://bronze@stlagunitas.dfs.core.windows.net/distribuicao/",
        "abfss://silver@stlagunitas.dfs.core.windows.net/distribuicao/",
    )
    print(f"Silver distribuicao: {count} records processed")
