--
-- PostgreSQL database dump
--

-- Dumped from database version 11.19 (Debian 11.19-1.pgdg110+1)
-- Dumped by pg_dump version 11.19 (Debian 11.19-1.pgdg110+1)

-- Started on 2023-05-09 21:55:22 UTC

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

DROP DATABASE IF EXISTS archive;
--
-- TOC entry 2988 (class 1262 OID 16384)
-- Name: archive; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE archive WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'en_US.utf8' LC_CTYPE = 'en_US.utf8';


ALTER DATABASE archive OWNER TO postgres;

\connect archive

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 201 (class 1255 OID 16401)
-- Name: doc_ins(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.doc_ins() RETURNS trigger
    LANGUAGE plpgsql
    AS $$declare
	last_chain bigint;
begin

lock table blockchain in access share mode;

last_chain = (select max(op_seq) from blockchain);

if new.op_seq <= (select op_seq from blockchain
				    where op_seq = last_chain
				 ) 
then
	raise exception check_violation
	using message = 'op_seq';
end if;

if new.op_stamp <= (select op_stamp from blockchain
				      where op_seq = last_chain
				   ) 
then
	-- FIXME: allow small delta?
	-- 
	raise exception check_violation
	using message = 'op_stamp';
end if;

return new;
end$$;


ALTER FUNCTION public.doc_ins() OWNER TO postgres;

--
-- TOC entry 202 (class 1255 OID 16402)
-- Name: reject_delete(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.reject_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$begin
	raise exception check_violation
	using message = 'delete';
end$$;


ALTER FUNCTION public.reject_delete() OWNER TO postgres;

--
-- TOC entry 203 (class 1255 OID 16403)
-- Name: reject_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.reject_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$begin
	raise exception check_violation
	using message = 'update';
end$$;


ALTER FUNCTION public.reject_update() OWNER TO postgres;

--
-- TOC entry 196 (class 1259 OID 16404)
-- Name: op_seq_gen; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.op_seq_gen
    START WITH 1000
    INCREMENT BY 1000
    MINVALUE 1000
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.op_seq_gen OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 197 (class 1259 OID 16406)
-- Name: blockchain; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.blockchain (
    op_seq bigint DEFAULT nextval('public.op_seq_gen'::regclass) NOT NULL,
    op_stamp timestamp with time zone NOT NULL,
    op_sign text NOT NULL,
    op_sign_stamp timestamp with time zone NOT NULL,
    previous_sign text NOT NULL
);


ALTER TABLE public.blockchain OWNER TO postgres;

--
-- TOC entry 2990 (class 0 OID 0)
-- Dependencies: 197
-- Name: TABLE blockchain; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.blockchain IS 'стандартный блокчейн
каждая такая запись закрывает предыдущий блок и открывает новый
допустимы ТОЛЬКО вставки
все операции, отличающиеся по времени последнего более, чем на время жизни блока, должны отвергаться
все операции, чей номер меньше последнего блока, должны отвергаться
все операции, с меткой подписи меньше блока должны отвергаться (допустим НЕБОЛЬШОЙ отступ в прошлое)
--
закрытие блок
1. блок собирает номера всех операций в нем + их подписи (и берет себе номер!)
2. подписывает (с меткой времени)
3. создает новую запись (в том числе пишет собственный номер)

';


--
-- TOC entry 198 (class 1259 OID 16413)
-- Name: doc_extension; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.doc_extension (
    op_seq bigint DEFAULT nextval('public.op_seq_gen'::regclass) NOT NULL,
    op_stamp timestamp with time zone NOT NULL,
    op_sign text NOT NULL,
    op_sign_stamp timestamp with time zone NOT NULL,
    our_number character varying(100) NOT NULL,
    parameter text NOT NULL,
    value text
);


ALTER TABLE public.doc_extension OWNER TO postgres;

--
-- TOC entry 2991 (class 0 OID 0)
-- Dependencies: 198
-- Name: TABLE doc_extension; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.doc_extension IS 'расширенные значения для документа
таблица ключ->значение, привязанная к конкретному документу
допустимы ТОЛЬКО вставки, лог не нужен
текущее значение - это последнее значение по seq (если не удалено)
значение NULL удалает 
';


--
-- TOC entry 199 (class 1259 OID 16420)
-- Name: doc_termination; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.doc_termination (
    op_seq bigint DEFAULT nextval('public.op_seq_gen'::regclass) NOT NULL,
    op_stamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    op_sign text NOT NULL,
    op_sign_stamp timestamp with time zone NOT NULL,
    our_number character varying(100) NOT NULL,
    replacement character varying(100)
);


ALTER TABLE public.doc_termination OWNER TO postgres;

--
-- TOC entry 2992 (class 0 OID 0)
-- Dependencies: 199
-- Name: TABLE doc_termination; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.doc_termination IS 'таблица окончания времени жизни документы
допустимы ТОЛЬКО вставки, лог не нужен
причины бывают две - отмена и замена
op_* - см. docs
our_number - отменяемый/заменяемый номер
replacement - заменающий номер (если null - отмена!)
для каждого документа может быть только ОДНА запись тут
';


--
-- TOC entry 200 (class 1259 OID 16428)
-- Name: docs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.docs (
    last_name character varying(500),
    first_name character varying(500),
    middle_name character varying(500),
    prefix_name character varying(500),
    last_name_lat character varying(500),
    first_name_lat character varying(500),
    middle_name_lat character varying(500),
    prefix_name_lat character varying(500),
    bdate date,
    bplace character varying(500),
    docdate date,
    spec_code character varying(100),
    spec_name character varying(1000),
    infoset json,
    ed_level character varying(20),
    doctype_kind character varying(20),
    year_completion integer,
    signed text,
    qualification character varying(250),
    our_number character varying(30) NOT NULL,
    country character varying(2),
    infoset_parsed jsonb,
    infoset_orginfo jsonb,
    gender smallint,
    course_length character varying(30),
    signers jsonb,
    signatures jsonb,
    doctype_name character varying(200),
    gov_doc boolean,
    our_date date DEFAULT CURRENT_DATE NOT NULL,
    op_stamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    op_seq bigint DEFAULT nextval('public.op_seq_gen'::regclass) NOT NULL,
    op_sign text NOT NULL,
    op_sign_stamp timestamp with time zone NOT NULL
);


ALTER TABLE public.docs OWNER TO postgres;

--
-- TOC entry 2993 (class 0 OID 0)
-- Dependencies: 200
-- Name: TABLE docs; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.docs IS 'в эту таблицу можно ТОЛЬКО вставлять. (поэтому лог не нужен)
op_* -  управляющие поля
op_stamp - метка времени вставки. серверная. ненадежная
op_seq - глобальный последовательный номер операции на сервере (могут быть пропуски). из последовательности
op_sign - подпись данных (сервер ее НЕ проверяет, но можно проверить извне)
op_sing_stamp - время подписи (от сервера подписи, надежное)';


--
-- TOC entry 2994 (class 0 OID 0)
-- Dependencies: 200
-- Name: COLUMN docs.gender; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.docs.gender IS '1 - male
0 - female';


--
-- TOC entry 2995 (class 0 OID 0)
-- Dependencies: 200
-- Name: COLUMN docs.signers; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.docs.signers IS 'array of
{
c: path 
, id: person
, i:[position,f,i,o,fio]
}';


--
-- TOC entry 2852 (class 2606 OID 16438)
-- Name: docs docs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.docs
    ADD CONSTRAINT docs_pkey PRIMARY KEY (our_number);


--
-- TOC entry 2853 (class 2620 OID 16439)
-- Name: blockchain del; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER del BEFORE DELETE ON public.blockchain FOR EACH ROW EXECUTE PROCEDURE public.reject_delete();


--
-- TOC entry 2855 (class 2620 OID 16440)
-- Name: doc_extension del; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER del BEFORE DELETE ON public.doc_extension FOR EACH ROW EXECUTE PROCEDURE public.reject_delete();


--
-- TOC entry 2857 (class 2620 OID 16441)
-- Name: doc_termination del; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER del BEFORE DELETE ON public.doc_termination FOR EACH ROW EXECUTE PROCEDURE public.reject_delete();


--
-- TOC entry 2859 (class 2620 OID 16442)
-- Name: docs del; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER del BEFORE DELETE ON public.docs FOR EACH ROW EXECUTE PROCEDURE public.reject_delete();


--
-- TOC entry 2860 (class 2620 OID 16443)
-- Name: docs ins; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER ins BEFORE INSERT ON public.docs FOR EACH ROW EXECUTE PROCEDURE public.doc_ins();


--
-- TOC entry 2854 (class 2620 OID 16444)
-- Name: blockchain upd; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER upd BEFORE UPDATE ON public.blockchain FOR EACH ROW EXECUTE PROCEDURE public.reject_update();


--
-- TOC entry 2856 (class 2620 OID 16445)
-- Name: doc_extension upd; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER upd BEFORE UPDATE ON public.doc_extension FOR EACH ROW EXECUTE PROCEDURE public.reject_update();


--
-- TOC entry 2858 (class 2620 OID 16446)
-- Name: doc_termination upd; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER upd BEFORE UPDATE ON public.doc_termination FOR EACH ROW EXECUTE PROCEDURE public.reject_update();


--
-- TOC entry 2861 (class 2620 OID 16447)
-- Name: docs upd; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER upd BEFORE UPDATE ON public.docs FOR EACH ROW EXECUTE PROCEDURE public.reject_update();


--
-- TOC entry 2989 (class 0 OID 0)
-- Dependencies: 3
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO PUBLIC;


--
-- TOC entry 2996 (class 0 OID 0)
-- Dependencies: 200
-- Name: TABLE docs; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE public.docs TO user_backend;


-- Completed on 2023-05-09 21:55:22 UTC

--
-- PostgreSQL database dump complete
--

