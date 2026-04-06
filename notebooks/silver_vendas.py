# Databricks notebook source
# silver_vendas.py — Transformação da camada Silver para dados de vendas
# Este notebook é deployado via CI/CD pipeline para o workspace Databricks

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

def transform_vendas(spark, source_path, target_path):
    """Transforma dados brutos de vendas (Bronze) para Silver."""
    df_bronze = spark.read.format("delta").load(source_path)

    df_silver = (
        df_bronze
        .filter(F.col("data_venda").isNotNull())
        .withColumn("valor_total", F.col("quantidade") * F.col("preco_unitario"))
        .withColumn("ano_mes", F.date_format(F.col("data_venda"), "yyyy-MM"))
        .dropDuplicates(["id_transacao"])
    )

    df_silver.write.format("delta").mode("overwrite").save(target_path)
    return df_silver.count()


if __name__ == "__main__":
    spark = SparkSession.builder.appName("silver_vendas").getOrCreate()
    count = transform_vendas(
        spark,
        "abfss://bronze@stlagunitas.dfs.core.windows.net/vendas/",
        "abfss://silver@stlagunitas.dfs.core.windows.net/vendas/",
    )
    print(f"Silver vendas: {count} records processed")
