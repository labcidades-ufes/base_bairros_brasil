## DAG TEMPLATE

Pipeline de coleta e padronização da malha oficial de bairros do Brasil, extraída dos shapefiles do Censo Demográfico 2022 publicados pelo IBGE. Cobre todos os estados com dados disponíveis e preserva a geometria dos bairros na camada silver.

## Estrutura do projeto

- `coleta/`: detecta o Censo mais recente disponível, baixa os shapefiles de todas as UFs, converte geometria para WKT e salva na camada bronze.
- `pre_processamento/`: valida duplicatas, verifica geometrias e normaliza campos de texto para a camada silver.
- `processamento/`: aplica limpeza de texto e produz o schema final para a camada gold.
- `utils.R`: funções compartilhadas para leitura/escrita de dados no MinIO via DuckDB.
- `base_bairros_brasil.py`: DAG do Airflow orquestrando as três etapas via DockerOperator.

## Fluxo base do pipeline

1. Coleta: FTP IBGE (Censo 2022) → bronze
2. Pré-processamento: bronze → silver
3. Processamento: silver → gold

## Convenção de camadas

- Bronze: atributos dos shapefiles de todas as UFs empilhados, com geometria convertida para WKT e metadados de coleta
- Silver: campos renomeados para schema padrão, encoding validado e geometria preservada em `geometry_wkt`
- Gold: schema final com texto padronizado em maiúsculas sem acento — geometria não incluída (disponível na silver)

## Fonte oficial

| Recurso | URL |
|---|---|
| FTP Malhas Censo 2022 | https://geoftp.ibge.gov.br/organizacao_do_territorio/malhas_territoriais/malhas_de_setores_censitarios__divisoes_intramunicipais/ |

## Detecção automática de versão

O script de coleta testa anos de Censo disponíveis via HEAD request no FTP do IBGE. Quando o IBGE publicar a malha de bairros do próximo Censo, basta adicionar o ano ao vetor `ANOS_CANDIDATOS` no script de coleta.

## Cobertura

- **25 de 27 UFs** com dados disponíveis no Censo 2022
- **DF e TO** não possuem shapefile de bairros publicado pelo IBGE para o Censo 2022 — ausência esperada e registrada em log

## Observação sobre encoding

Os shapefiles do Censo 2022 utilizam UTF-8 nativamente. O script de coleta lê os arquivos sem forçar encoding (`st_read()` padrão) e nenhuma recodificação é aplicada no pipeline — os caracteres especiais do português são preservados corretamente.

## Validações aplicadas no pré-processamento

- Ausência de `cd_bairro` duplicado dentro da mesma UF
- `geometry_wkt` preenchida para todos os registros
- Contagem de UFs com dados (esperado: 25/27)
- Ausência de caracteres de encoding inválido (símbolo `\ufffd`)

## Schema gold

```
cd_bairro            — código oficial do bairro (IBGE)
nome_bairro          — nome em maiúsculas sem acento (uso em joins)
nome_bairro_original — nome exato conforme publicado pelo IBGE
cd_municipio         — código IBGE do município (7 dígitos)
nome_municipio       — nome do município padronizado
cd_distrito          — código do distrito
nome_distrito        — nome do distrito padronizado
sigla_uf             — sigla da UF (ex: "ES")
ano_censo            — ano do Censo Demográfico utilizado
```

> A geometria de cada bairro está disponível na camada silver como `geometry_wkt` (formato WKT).
> Para análises espaciais, consuma a silver diretamente.
