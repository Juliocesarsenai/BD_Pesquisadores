
-- 1. Construindo o Documento de Busca

SELECT 
    pesquisadores.nome || ' ' || coalesce((string_agg(producoes.nomeartigo, ' ')), '') AS document
FROM public.pesquisadores
LEFT JOIN public.producoes ON producoes.pesquisadores_id = pesquisadores.pesquisadores_id
GROUP BY pesquisadores.pesquisadores_id;


-- 2. Converter o Texto em tsvector

SELECT 
    to_tsvector('portuguese', 
        coalesce(prod.nomeartigo, '') || ' ' || coalesce(pesq.nome, '')
    ) AS document
FROM public.producoes prod
JOIN public.pesquisadores pesq ON pesq.pesquisadores_id = prod.pesquisadores_id;


-- 3. Realizando Consultas

SELECT pid, p_title
FROM (
    SELECT 
        prod.producoes_id AS pid,
        prod.nomeartigo AS p_title,
        to_tsvector('portuguese', coalesce(prod.nomeartigo, '')) ||
        to_tsvector('portuguese', coalesce(pesq.nome, '')) ||
        to_tsvector('portuguese', coalesce(prod.issn, '')) AS document
    FROM public.producoes prod
    JOIN public.pesquisadores pesq ON pesq.pesquisadores_id = prod.pesquisadores_id
) p_search
WHERE p_search.document @@ to_tsquery('portuguese', 'Organizacional');


-- 4. Classificando Documentos por Relevância (ts_rank)

SELECT pid, p_title
FROM (
    SELECT 
        prod.producoes_id AS pid,
        prod.nomeartigo AS p_title,
        setweight(to_tsvector('portuguese', coalesce(prod.nomeartigo, '')), 'A') ||
        setweight(to_tsvector('portuguese', coalesce(pesq.nome, '')), 'B') ||
        setweight(to_tsvector('simple', coalesce(prod.issn, '')), 'C') AS document
    FROM public.producoes prod
    JOIN public.pesquisadores pesq ON pesq.pesquisadores_id = prod.pesquisadores_id
) p_search
WHERE p_search.document @@ to_tsquery('portuguese', 'Perspectivas')
ORDER BY ts_rank(p_search.document, to_tsquery('portuguese', 'Perspectivas')) DESC;


-- 5. Trabalhando com Caracteres Acentuados 

SELECT 
    pesq.nome AS nomePesquisador, 
    prod.nomeartigo AS nomeArtigo,
    to_tsvector('portuguese', unaccent(coalesce(prod.nomeartigo, ''))) ||
    to_tsvector('simple', unaccent(coalesce(pesq.nome, ''))) ||
    to_tsvector('simple', unaccent(coalesce(prod.issn, ''))) AS document
FROM public.producoes prod
JOIN public.pesquisadores pesq ON pesq.pesquisadores_id = prod.pesquisadores_id;


-- 6. Otimização e Indexação 

DROP INDEX IF EXISTS idx_fts_producoes;

CREATE INDEX idx_fts_producoes ON public.producoes
USING gin(
    (
        setweight(to_tsvector('portuguese', coalesce(nomeartigo, '')), 'A') ||
        setweight(to_tsvector('simple', coalesce(issn, '')), 'B')
    )
);

-- 7. Materialized View para Pesquisas entre Tabelas

DROP MATERIALIZED VIEW IF EXISTS search_index CASCADE;

CREATE MATERIALIZED VIEW search_index AS
SELECT 
    prod.producoes_id AS pid,
    prod.nomeartigo AS p_title,
    pesq.nome AS autor_nome,
    setweight(to_tsvector('portuguese', coalesce(prod.nomeartigo, '')), 'A') ||
    setweight(to_tsvector('portuguese', coalesce(pesq.nome, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(prod.issn, '')), 'C') AS document
FROM public.producoes prod
JOIN public.pesquisadores pesq ON pesq.pesquisadores_id = prod.pesquisadores_id;

CREATE INDEX idx_fts_search ON search_index USING gin(document);

-- Consulta na Materialized View
SELECT 
    pid AS producao_id, 
    p_title AS artigo_titulo,
    autor_nome
FROM search_index
WHERE document @@ to_tsquery('portuguese', 'Estrutura & Organizacional')
ORDER BY ts_rank(document, to_tsquery('portuguese', 'Estrutura & Organizacional')) DESC;


-- 8. Erros de Ortografia e Dicionário de Termos (pg_trgm)

CREATE EXTENSION IF NOT EXISTS pg_trgm;

DROP MATERIALIZED VIEW IF EXISTS unique_lexeme CASCADE;

CREATE MATERIALIZED VIEW unique_lexeme AS
SELECT word FROM ts_stat(
'SELECT to_tsvector(''simple'', public.producoes.nomeartigo) ||
        to_tsvector(''simple'', public.pesquisadores.nome) ||
        to_tsvector(''simple'', coalesce(public.producoes.issn, '' ''))
FROM public.producoes
JOIN public.pesquisadores ON public.pesquisadores.pesquisadores_id = public.producoes.pesquisadores_id');

CREATE INDEX words_idx ON unique_lexeme USING gin(word gin_trgm_ops);

REFRESH MATERIALIZED VIEW unique_lexeme;

-- Consulta de Similaridade / Tolerância a Erros
SELECT word
FROM unique_lexeme
WHERE similarity(word, 'estrutra') > 0.3
ORDER BY word <-> 'estrutra'
LIMIT 1;