--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5 (Debian 17.5-1.pgdg120+1)
-- Dumped by pg_dump version 17.5 (Debian 17.5-1.pgdg120+1)

-- Started on 2025-06-18 22:11:06 UTC

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 4067 (class 0 OID 0)
-- Dependencies: 6
-- Name: SCHEMA "public"; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA "public" IS 'standard public schema';


--
-- TOC entry 3 (class 3079 OID 25169)
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "public";


--
-- TOC entry 4068 (class 0 OID 0)
-- Dependencies: 3
-- Name: EXTENSION "pgcrypto"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "pgcrypto" IS 'cryptographic functions';


--
-- TOC entry 2 (class 3079 OID 25158)
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "public";


--
-- TOC entry 4069 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- TOC entry 293 (class 1255 OID 25694)
-- Name: cleanup_expired_sessions_secure(); Type: FUNCTION; Schema: public; Owner: veza
--

CREATE FUNCTION "public"."cleanup_expired_sessions_secure"() RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM user_sessions_secure 
    WHERE expires_at < NOW() OR last_used < NOW() - INTERVAL '30 days';
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;


ALTER FUNCTION "public"."cleanup_expired_sessions_secure"() OWNER TO "veza";

--
-- TOC entry 292 (class 1255 OID 25155)
-- Name: cleanup_old_audit_logs(); Type: FUNCTION; Schema: public; Owner: veza
--

CREATE FUNCTION "public"."cleanup_old_audit_logs"() RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM audit_logs WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '30 days';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;


ALTER FUNCTION "public"."cleanup_old_audit_logs"() OWNER TO "veza";

--
-- TOC entry 294 (class 1255 OID 25695)
-- Name: cleanup_old_data_secure(); Type: FUNCTION; Schema: public; Owner: veza
--

CREATE FUNCTION "public"."cleanup_old_data_secure"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Supprimer les sessions expirées
    PERFORM cleanup_expired_sessions_secure();
    
    -- Nettoyer les événements de sécurité anciens
    DELETE FROM security_events_secure 
    WHERE created_at < NOW() - INTERVAL '6 months' AND severity = 'info';
    
    RAISE NOTICE 'Nettoyage terminé';
END;
$$;


ALTER FUNCTION "public"."cleanup_old_data_secure"() OWNER TO "veza";

--
-- TOC entry 352 (class 1255 OID 25696)
-- Name: handle_mentions_secure(); Type: FUNCTION; Schema: public; Owner: veza
--

CREATE FUNCTION "public"."handle_mentions_secure"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Extraire les mentions @username du contenu
    INSERT INTO message_mentions_secure (message_id, user_id)
    SELECT NEW.id, u.id
    FROM users u
    WHERE NEW.content ~* ('@' || u.username || '\M')
      AND u.id != NEW.from_user
    ON CONFLICT (message_id, user_id) DO NOTHING;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_mentions_secure"() OWNER TO "veza";

--
-- TOC entry 291 (class 1255 OID 24860)
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: veza
--

CREATE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "veza";

SET default_tablespace = '';

SET default_table_access_method = "heap";

--
-- TOC entry 268 (class 1259 OID 25120)
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."audit_logs" (
    "id" integer NOT NULL,
    "user_id" integer,
    "action" character varying(100) NOT NULL,
    "resource_type" character varying(50),
    "resource_id" character varying(100),
    "details" "jsonb",
    "ip_address" "inet",
    "user_agent" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."audit_logs" OWNER TO "veza";

--
-- TOC entry 267 (class 1259 OID 25119)
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."audit_logs_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."audit_logs_id_seq" OWNER TO "veza";

--
-- TOC entry 4070 (class 0 OID 0)
-- Dependencies: 267
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."audit_logs_id_seq" OWNED BY "public"."audit_logs"."id";


--
-- TOC entry 246 (class 1259 OID 24827)
-- Name: categories; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."categories" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL,
    "description" "text" DEFAULT ''::"text",
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "updated_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."categories" OWNER TO "veza";

--
-- TOC entry 245 (class 1259 OID 24826)
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."categories_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."categories_id_seq" OWNER TO "veza";

--
-- TOC entry 4071 (class 0 OID 0)
-- Dependencies: 245
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."categories_id_seq" OWNED BY "public"."categories"."id";


--
-- TOC entry 222 (class 1259 OID 16436)
-- Name: files; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."files" (
    "id" integer NOT NULL,
    "product_id" integer NOT NULL,
    "filename" "text" NOT NULL,
    "url" "text" NOT NULL,
    "type" "text" NOT NULL,
    "uploaded_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."files" OWNER TO "veza";

--
-- TOC entry 221 (class 1259 OID 16435)
-- Name: files_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."files_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."files_id_seq" OWNER TO "veza";

--
-- TOC entry 4072 (class 0 OID 0)
-- Dependencies: 221
-- Name: files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."files_id_seq" OWNED BY "public"."files"."id";


--
-- TOC entry 224 (class 1259 OID 16451)
-- Name: internal_documents; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."internal_documents" (
    "id" integer NOT NULL,
    "product_id" integer NOT NULL,
    "title" "text" NOT NULL,
    "filename" "text" NOT NULL,
    "url" "text" NOT NULL,
    "type" "text" NOT NULL,
    "uploaded_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."internal_documents" OWNER TO "veza";

--
-- TOC entry 223 (class 1259 OID 16450)
-- Name: internal_documents_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."internal_documents_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."internal_documents_id_seq" OWNER TO "veza";

--
-- TOC entry 4073 (class 0 OID 0)
-- Dependencies: 223
-- Name: internal_documents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."internal_documents_id_seq" OWNED BY "public"."internal_documents"."id";


--
-- TOC entry 238 (class 1259 OID 24708)
-- Name: listings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."listings" (
    "id" integer NOT NULL,
    "user_id" integer NOT NULL,
    "product_id" integer NOT NULL,
    "description" "text" NOT NULL,
    "state" "text" NOT NULL,
    "price" integer,
    "exchange_for" "text",
    "images" "text"[],
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."listings" OWNER TO "postgres";

--
-- TOC entry 237 (class 1259 OID 24707)
-- Name: listings_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."listings_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."listings_id_seq" OWNER TO "postgres";

--
-- TOC entry 4075 (class 0 OID 0)
-- Dependencies: 237
-- Name: listings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."listings_id_seq" OWNED BY "public"."listings"."id";


--
-- TOC entry 277 (class 1259 OID 25308)
-- Name: message_mentions_enhanced; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."message_mentions_enhanced" (
    "id" bigint NOT NULL,
    "message_id" bigint NOT NULL,
    "user_id" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_read" boolean DEFAULT false
);


ALTER TABLE "public"."message_mentions_enhanced" OWNER TO "veza";

--
-- TOC entry 4077 (class 0 OID 0)
-- Dependencies: 277
-- Name: TABLE "message_mentions_enhanced"; Type: COMMENT; Schema: public; Owner: veza
--

COMMENT ON TABLE "public"."message_mentions_enhanced" IS 'Mentions d''utilisateurs';


--
-- TOC entry 276 (class 1259 OID 25307)
-- Name: message_mentions_enhanced_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."message_mentions_enhanced_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."message_mentions_enhanced_id_seq" OWNER TO "veza";

--
-- TOC entry 4078 (class 0 OID 0)
-- Dependencies: 276
-- Name: message_mentions_enhanced_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."message_mentions_enhanced_id_seq" OWNED BY "public"."message_mentions_enhanced"."id";


--
-- TOC entry 288 (class 1259 OID 25646)
-- Name: message_mentions_secure; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."message_mentions_secure" (
    "id" bigint NOT NULL,
    "message_id" integer NOT NULL,
    "user_id" integer NOT NULL,
    "is_read" boolean DEFAULT false,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."message_mentions_secure" OWNER TO "veza";

--
-- TOC entry 287 (class 1259 OID 25645)
-- Name: message_mentions_secure_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."message_mentions_secure_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."message_mentions_secure_id_seq" OWNER TO "veza";

--
-- TOC entry 4079 (class 0 OID 0)
-- Dependencies: 287
-- Name: message_mentions_secure_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."message_mentions_secure_id_seq" OWNED BY "public"."message_mentions_secure"."id";


--
-- TOC entry 258 (class 1259 OID 25008)
-- Name: message_reactions; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."message_reactions" (
    "id" integer NOT NULL,
    "message_id" integer NOT NULL,
    "user_id" integer NOT NULL,
    "reaction_type" character varying(100) NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."message_reactions" OWNER TO "veza";

--
-- TOC entry 4080 (class 0 OID 0)
-- Dependencies: 258
-- Name: TABLE "message_reactions"; Type: COMMENT; Schema: public; Owner: veza
--

COMMENT ON TABLE "public"."message_reactions" IS 'Table des réactions aux messages (like, love, etc.)';


--
-- TOC entry 275 (class 1259 OID 25288)
-- Name: message_reactions_enhanced; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."message_reactions_enhanced" (
    "id" bigint NOT NULL,
    "message_id" bigint NOT NULL,
    "user_id" integer NOT NULL,
    "emoji" character varying(100) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."message_reactions_enhanced" OWNER TO "veza";

--
-- TOC entry 4081 (class 0 OID 0)
-- Dependencies: 275
-- Name: TABLE "message_reactions_enhanced"; Type: COMMENT; Schema: public; Owner: veza
--

COMMENT ON TABLE "public"."message_reactions_enhanced" IS 'Réactions aux messages';


--
-- TOC entry 274 (class 1259 OID 25287)
-- Name: message_reactions_enhanced_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."message_reactions_enhanced_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."message_reactions_enhanced_id_seq" OWNER TO "veza";

--
-- TOC entry 4082 (class 0 OID 0)
-- Dependencies: 274
-- Name: message_reactions_enhanced_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."message_reactions_enhanced_id_seq" OWNED BY "public"."message_reactions_enhanced"."id";


--
-- TOC entry 257 (class 1259 OID 25007)
-- Name: message_reactions_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."message_reactions_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."message_reactions_id_seq" OWNER TO "veza";

--
-- TOC entry 4083 (class 0 OID 0)
-- Dependencies: 257
-- Name: message_reactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."message_reactions_id_seq" OWNED BY "public"."message_reactions"."id";


--
-- TOC entry 228 (class 1259 OID 16479)
-- Name: messages; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."messages" (
    "id" integer NOT NULL,
    "from_user" integer,
    "to_user" integer,
    "room" "text",
    "content" "text" NOT NULL,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "message_type" character varying(20) DEFAULT 'text'::character varying,
    "reply_to_id" integer,
    "is_edited" boolean DEFAULT false,
    "edited_at" timestamp with time zone,
    "metadata" "jsonb",
    "is_pinned" boolean DEFAULT false,
    "thread_count" integer DEFAULT 0,
    "status" character varying(20) DEFAULT 'sent'::character varying,
    CONSTRAINT "chk_message_content_length" CHECK (("length"("content") <= 4000))
);


ALTER TABLE "public"."messages" OWNER TO "veza";

--
-- TOC entry 273 (class 1259 OID 25249)
-- Name: messages_enhanced; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."messages_enhanced" (
    "id" bigint NOT NULL,
    "message_type" character varying(20) NOT NULL,
    "content" "text" NOT NULL,
    "author_id" integer NOT NULL,
    "author_username" character varying(50) NOT NULL,
    "room_id" character varying(100),
    "recipient_id" integer,
    "recipient_username" character varying(50),
    "parent_message_id" bigint,
    "thread_count" integer DEFAULT 0,
    "status" character varying(20) DEFAULT 'sent'::character varying,
    "is_pinned" boolean DEFAULT false,
    "is_edited" boolean DEFAULT false,
    "original_content" "text",
    "is_flagged" boolean DEFAULT false,
    "moderation_notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone,
    CONSTRAINT "message_destination_check" CHECK ((((("message_type")::"text" = 'room_message'::"text") AND ("room_id" IS NOT NULL) AND ("recipient_id" IS NULL)) OR ((("message_type")::"text" = 'direct_message'::"text") AND ("room_id" IS NULL) AND ("recipient_id" IS NOT NULL)) OR (("message_type")::"text" = 'system_message'::"text"))),
    CONSTRAINT "messages_enhanced_content_check" CHECK (("length"("content") <= 4000)),
    CONSTRAINT "messages_enhanced_message_type_check" CHECK ((("message_type")::"text" = ANY ((ARRAY['room_message'::character varying, 'direct_message'::character varying, 'system_message'::character varying])::"text"[]))),
    CONSTRAINT "messages_enhanced_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['sent'::character varying, 'delivered'::character varying, 'read'::character varying, 'edited'::character varying, 'deleted'::character varying])::"text"[])))
);


ALTER TABLE "public"."messages_enhanced" OWNER TO "veza";

--
-- TOC entry 4084 (class 0 OID 0)
-- Dependencies: 273
-- Name: TABLE "messages_enhanced"; Type: COMMENT; Schema: public; Owner: veza
--

COMMENT ON TABLE "public"."messages_enhanced" IS 'Messages unifiés avec séparation logique DM/salons';


--
-- TOC entry 272 (class 1259 OID 25248)
-- Name: messages_enhanced_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."messages_enhanced_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."messages_enhanced_id_seq" OWNER TO "veza";

--
-- TOC entry 4085 (class 0 OID 0)
-- Dependencies: 272
-- Name: messages_enhanced_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."messages_enhanced_id_seq" OWNED BY "public"."messages_enhanced"."id";


--
-- TOC entry 227 (class 1259 OID 16478)
-- Name: messages_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."messages_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."messages_id_seq" OWNER TO "veza";

--
-- TOC entry 4086 (class 0 OID 0)
-- Dependencies: 227
-- Name: messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."messages_id_seq" OWNED BY "public"."messages"."id";


--
-- TOC entry 250 (class 1259 OID 24885)
-- Name: migrations; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."migrations" (
    "id" integer NOT NULL,
    "filename" character varying(255) NOT NULL,
    "applied_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."migrations" OWNER TO "veza";

--
-- TOC entry 249 (class 1259 OID 24884)
-- Name: migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."migrations_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."migrations_id_seq" OWNER TO "veza";

--
-- TOC entry 4087 (class 0 OID 0)
-- Dependencies: 249
-- Name: migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."migrations_id_seq" OWNED BY "public"."migrations"."id";


--
-- TOC entry 264 (class 1259 OID 25078)
-- Name: notifications; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."notifications" (
    "id" integer NOT NULL,
    "user_id" integer NOT NULL,
    "type" character varying(50) NOT NULL,
    "title" character varying(255) NOT NULL,
    "content" "text" NOT NULL,
    "metadata" "jsonb",
    "is_read" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "read_at" timestamp with time zone
);


ALTER TABLE "public"."notifications" OWNER TO "veza";

--
-- TOC entry 4088 (class 0 OID 0)
-- Dependencies: 264
-- Name: TABLE "notifications"; Type: COMMENT; Schema: public; Owner: veza
--

COMMENT ON TABLE "public"."notifications" IS 'Table des notifications push/in-app';


--
-- TOC entry 263 (class 1259 OID 25077)
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."notifications_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."notifications_id_seq" OWNER TO "veza";

--
-- TOC entry 4089 (class 0 OID 0)
-- Dependencies: 263
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."notifications_id_seq" OWNED BY "public"."notifications"."id";


--
-- TOC entry 240 (class 1259 OID 24729)
-- Name: offers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."offers" (
    "id" integer NOT NULL,
    "listing_id" integer NOT NULL,
    "from_user_id" integer NOT NULL,
    "proposed_product_id" integer NOT NULL,
    "message" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."offers" OWNER TO "postgres";

--
-- TOC entry 239 (class 1259 OID 24728)
-- Name: offers_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."offers_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."offers_id_seq" OWNER TO "postgres";

--
-- TOC entry 4091 (class 0 OID 0)
-- Dependencies: 239
-- Name: offers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."offers_id_seq" OWNED BY "public"."offers"."id";


--
-- TOC entry 248 (class 1259 OID 24841)
-- Name: product_documents; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."product_documents" (
    "id" integer NOT NULL,
    "product_id" integer NOT NULL,
    "name" "text" NOT NULL,
    "description" "text" DEFAULT ''::"text",
    "file_type" "text" NOT NULL,
    "file_path" "text" NOT NULL,
    "file_size" bigint DEFAULT 0,
    "uploaded_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "product_documents_file_type_check" CHECK (("file_type" = ANY (ARRAY['manual'::"text", 'datasheet'::"text", 'warranty'::"text", 'image'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."product_documents" OWNER TO "veza";

--
-- TOC entry 247 (class 1259 OID 24840)
-- Name: product_documents_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."product_documents_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."product_documents_id_seq" OWNER TO "veza";

--
-- TOC entry 4093 (class 0 OID 0)
-- Dependencies: 247
-- Name: product_documents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."product_documents_id_seq" OWNED BY "public"."product_documents"."id";


--
-- TOC entry 242 (class 1259 OID 24771)
-- Name: products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."products" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL,
    "category_id" integer,
    "brand" "text" DEFAULT ''::"text",
    "model" "text" DEFAULT ''::"text",
    "description" "text" DEFAULT ''::"text",
    "price" numeric(10,2),
    "warranty_months" integer DEFAULT 0,
    "warranty_conditions" "text" DEFAULT ''::"text",
    "manufacturer_website" "text" DEFAULT ''::"text",
    "specifications" "text" DEFAULT ''::"text",
    "status" "text" DEFAULT 'active'::"text",
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "updated_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "products_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'discontinued'::"text", 'draft'::"text"])))
);


ALTER TABLE "public"."products" OWNER TO "postgres";

--
-- TOC entry 241 (class 1259 OID 24770)
-- Name: products_id_seq1; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."products_id_seq1"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."products_id_seq1" OWNER TO "postgres";

--
-- TOC entry 4095 (class 0 OID 0)
-- Dependencies: 241
-- Name: products_id_seq1; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."products_id_seq1" OWNED BY "public"."products"."id";


--
-- TOC entry 254 (class 1259 OID 24956)
-- Name: refresh_tokens; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."refresh_tokens" (
    "id" integer NOT NULL,
    "user_id" integer,
    "token" "text" NOT NULL,
    "expires_at" timestamp without time zone NOT NULL,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."refresh_tokens" OWNER TO "postgres";

--
-- TOC entry 253 (class 1259 OID 24955)
-- Name: refresh_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."refresh_tokens_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."refresh_tokens_id_seq" OWNER TO "postgres";

--
-- TOC entry 4098 (class 0 OID 0)
-- Dependencies: 253
-- Name: refresh_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."refresh_tokens_id_seq" OWNED BY "public"."refresh_tokens"."id";


--
-- TOC entry 235 (class 1259 OID 16560)
-- Name: ressource_tags; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."ressource_tags" (
    "ressource_id" integer NOT NULL,
    "tag_id" integer NOT NULL
);


ALTER TABLE "public"."ressource_tags" OWNER TO "postgres";

--
-- TOC entry 262 (class 1259 OID 25054)
-- Name: room_members; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."room_members" (
    "id" integer NOT NULL,
    "room_id" integer NOT NULL,
    "user_id" integer NOT NULL,
    "role" character varying(20) DEFAULT 'member'::character varying NOT NULL,
    "joined_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "last_read_at" timestamp with time zone
);


ALTER TABLE "public"."room_members" OWNER TO "veza";

--
-- TOC entry 4101 (class 0 OID 0)
-- Dependencies: 262
-- Name: TABLE "room_members"; Type: COMMENT; Schema: public; Owner: veza
--

COMMENT ON TABLE "public"."room_members" IS 'Table des membres de salon avec leurs rôles';


--
-- TOC entry 278 (class 1259 OID 25328)
-- Name: room_members_enhanced; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."room_members_enhanced" (
    "room_id" character varying(100) NOT NULL,
    "user_id" integer NOT NULL,
    "role" character varying(20) DEFAULT 'member'::character varying,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_read_message_id" bigint,
    CONSTRAINT "room_members_enhanced_role_check" CHECK ((("role")::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'moderator'::character varying, 'member'::character varying])::"text"[])))
);


ALTER TABLE "public"."room_members_enhanced" OWNER TO "veza";

--
-- TOC entry 261 (class 1259 OID 25053)
-- Name: room_members_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."room_members_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."room_members_id_seq" OWNER TO "veza";

--
-- TOC entry 4102 (class 0 OID 0)
-- Dependencies: 261
-- Name: room_members_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."room_members_id_seq" OWNED BY "public"."room_members"."id";


--
-- TOC entry 226 (class 1259 OID 16466)
-- Name: rooms; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."rooms" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL,
    "is_private" boolean DEFAULT false,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "creator_id" integer,
    "max_members" integer DEFAULT 1000,
    "description" "text",
    CONSTRAINT "chk_room_name_length" CHECK ((("length"("name") <= 50) AND ("length"("name") >= 1)))
);


ALTER TABLE "public"."rooms" OWNER TO "veza";

--
-- TOC entry 4103 (class 0 OID 0)
-- Dependencies: 226
-- Name: TABLE "rooms"; Type: COMMENT; Schema: public; Owner: veza
--

COMMENT ON TABLE "public"."rooms" IS 'Table des salons de chat avec métadonnées';


--
-- TOC entry 271 (class 1259 OID 25229)
-- Name: rooms_enhanced; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."rooms_enhanced" (
    "id" character varying(100) NOT NULL,
    "name" character varying(100) NOT NULL,
    "description" "text",
    "owner_id" integer NOT NULL,
    "is_public" boolean DEFAULT true NOT NULL,
    "is_archived" boolean DEFAULT false,
    "max_members" integer DEFAULT 1000,
    "member_count" integer DEFAULT 0,
    "message_count" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."rooms_enhanced" OWNER TO "veza";

--
-- TOC entry 225 (class 1259 OID 16465)
-- Name: rooms_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."rooms_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."rooms_id_seq" OWNER TO "veza";

--
-- TOC entry 4104 (class 0 OID 0)
-- Dependencies: 225
-- Name: rooms_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."rooms_id_seq" OWNED BY "public"."rooms"."id";


--
-- TOC entry 256 (class 1259 OID 24985)
-- Name: sanctions; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."sanctions" (
    "id" integer NOT NULL,
    "user_id" integer NOT NULL,
    "moderator_id" integer NOT NULL,
    "sanction_type" character varying(50) NOT NULL,
    "reason" character varying(100) NOT NULL,
    "message" "text",
    "expires_at" timestamp with time zone,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."sanctions" OWNER TO "veza";

--
-- TOC entry 4105 (class 0 OID 0)
-- Dependencies: 256
-- Name: TABLE "sanctions"; Type: COMMENT; Schema: public; Owner: veza
--

COMMENT ON TABLE "public"."sanctions" IS 'Table des sanctions de modération (warnings, mutes, bans)';


--
-- TOC entry 255 (class 1259 OID 24984)
-- Name: sanctions_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."sanctions_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."sanctions_id_seq" OWNER TO "veza";

--
-- TOC entry 4106 (class 0 OID 0)
-- Dependencies: 255
-- Name: sanctions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."sanctions_id_seq" OWNED BY "public"."sanctions"."id";


--
-- TOC entry 283 (class 1259 OID 25388)
-- Name: security_events_enhanced; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."security_events_enhanced" (
    "id" bigint NOT NULL,
    "event_type" character varying(50) NOT NULL,
    "severity" character varying(20) DEFAULT 'info'::character varying,
    "user_id" integer,
    "ip_address" "inet",
    "user_agent" "text",
    "details" "jsonb" DEFAULT '{}'::"jsonb",
    "success" boolean,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "security_events_enhanced_severity_check" CHECK ((("severity")::"text" = ANY ((ARRAY['debug'::character varying, 'info'::character varying, 'warning'::character varying, 'error'::character varying, 'critical'::character varying])::"text"[])))
);


ALTER TABLE "public"."security_events_enhanced" OWNER TO "veza";

--
-- TOC entry 4107 (class 0 OID 0)
-- Dependencies: 283
-- Name: TABLE "security_events_enhanced"; Type: COMMENT; Schema: public; Owner: veza
--

COMMENT ON TABLE "public"."security_events_enhanced" IS 'Journal de sécurité';


--
-- TOC entry 282 (class 1259 OID 25387)
-- Name: security_events_enhanced_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."security_events_enhanced_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."security_events_enhanced_id_seq" OWNER TO "veza";

--
-- TOC entry 4108 (class 0 OID 0)
-- Dependencies: 282
-- Name: security_events_enhanced_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."security_events_enhanced_id_seq" OWNED BY "public"."security_events_enhanced"."id";


--
-- TOC entry 286 (class 1259 OID 25623)
-- Name: security_events_secure; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."security_events_secure" (
    "id" bigint NOT NULL,
    "user_id" integer,
    "event_type" character varying(50) NOT NULL,
    "severity" character varying(20) DEFAULT 'info'::character varying,
    "description" "text" NOT NULL,
    "ip_address" "inet",
    "user_agent" "text",
    "additional_data" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone,
    "resolved_by" integer,
    CONSTRAINT "security_events_secure_severity_check" CHECK ((("severity")::"text" = ANY ((ARRAY['critical'::character varying, 'high'::character varying, 'medium'::character varying, 'low'::character varying, 'info'::character varying])::"text"[])))
);


ALTER TABLE "public"."security_events_secure" OWNER TO "veza";

--
-- TOC entry 285 (class 1259 OID 25622)
-- Name: security_events_secure_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."security_events_secure_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."security_events_secure_id_seq" OWNER TO "veza";

--
-- TOC entry 4109 (class 0 OID 0)
-- Dependencies: 285
-- Name: security_events_secure_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."security_events_secure_id_seq" OWNED BY "public"."security_events_secure"."id";


--
-- TOC entry 236 (class 1259 OID 16575)
-- Name: shared_ressource_tags; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."shared_ressource_tags" (
    "shared_ressource_id" integer NOT NULL,
    "tag_id" integer NOT NULL
);


ALTER TABLE "public"."shared_ressource_tags" OWNER TO "postgres";

--
-- TOC entry 232 (class 1259 OID 16532)
-- Name: shared_ressources; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."shared_ressources" (
    "id" integer NOT NULL,
    "title" "text" NOT NULL,
    "filename" "text" NOT NULL,
    "url" "text" NOT NULL,
    "type" "text" NOT NULL,
    "tags" "text"[],
    "uploader_id" integer NOT NULL,
    "is_public" boolean DEFAULT true,
    "uploaded_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "download_count" integer DEFAULT 0,
    "description" "text"
);


ALTER TABLE "public"."shared_ressources" OWNER TO "veza";

--
-- TOC entry 231 (class 1259 OID 16531)
-- Name: shared_ressources_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."shared_ressources_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."shared_ressources_id_seq" OWNER TO "veza";

--
-- TOC entry 4111 (class 0 OID 0)
-- Dependencies: 231
-- Name: shared_ressources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."shared_ressources_id_seq" OWNED BY "public"."shared_ressources"."id";


--
-- TOC entry 234 (class 1259 OID 16550)
-- Name: tags; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."tags" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL
);


ALTER TABLE "public"."tags" OWNER TO "postgres";

--
-- TOC entry 233 (class 1259 OID 16549)
-- Name: tags_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."tags_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."tags_id_seq" OWNER TO "postgres";

--
-- TOC entry 4113 (class 0 OID 0)
-- Dependencies: 233
-- Name: tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."tags_id_seq" OWNED BY "public"."tags"."id";


--
-- TOC entry 230 (class 1259 OID 16499)
-- Name: tracks; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."tracks" (
    "id" integer NOT NULL,
    "title" "text" NOT NULL,
    "filename" "text" NOT NULL,
    "artist" "text",
    "duration_seconds" integer,
    "tags" "text"[],
    "is_public" boolean DEFAULT true,
    "uploader_id" integer,
    "created_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."tracks" OWNER TO "veza";

--
-- TOC entry 229 (class 1259 OID 16498)
-- Name: tracks_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."tracks_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."tracks_id_seq" OWNER TO "veza";

--
-- TOC entry 4114 (class 0 OID 0)
-- Dependencies: 229
-- Name: tracks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."tracks_id_seq" OWNED BY "public"."tracks"."id";


--
-- TOC entry 260 (class 1259 OID 25029)
-- Name: user_blocks; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."user_blocks" (
    "id" integer NOT NULL,
    "blocker_id" integer NOT NULL,
    "blocked_id" integer NOT NULL,
    "reason" character varying(255),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "user_blocks_check" CHECK (("blocker_id" <> "blocked_id"))
);


ALTER TABLE "public"."user_blocks" OWNER TO "veza";

--
-- TOC entry 4115 (class 0 OID 0)
-- Dependencies: 260
-- Name: TABLE "user_blocks"; Type: COMMENT; Schema: public; Owner: veza
--

COMMENT ON TABLE "public"."user_blocks" IS 'Table des blocages entre utilisateurs';


--
-- TOC entry 280 (class 1259 OID 25347)
-- Name: user_blocks_enhanced; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."user_blocks_enhanced" (
    "id" bigint NOT NULL,
    "blocker_id" integer NOT NULL,
    "blocked_id" integer NOT NULL,
    "reason" character varying(500),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "no_self_block" CHECK (("blocker_id" <> "blocked_id"))
);


ALTER TABLE "public"."user_blocks_enhanced" OWNER TO "veza";

--
-- TOC entry 4116 (class 0 OID 0)
-- Dependencies: 280
-- Name: TABLE "user_blocks_enhanced"; Type: COMMENT; Schema: public; Owner: veza
--

COMMENT ON TABLE "public"."user_blocks_enhanced" IS 'Blocages entre utilisateurs';


--
-- TOC entry 279 (class 1259 OID 25346)
-- Name: user_blocks_enhanced_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."user_blocks_enhanced_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."user_blocks_enhanced_id_seq" OWNER TO "veza";

--
-- TOC entry 4117 (class 0 OID 0)
-- Dependencies: 279
-- Name: user_blocks_enhanced_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."user_blocks_enhanced_id_seq" OWNED BY "public"."user_blocks_enhanced"."id";


--
-- TOC entry 259 (class 1259 OID 25028)
-- Name: user_blocks_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."user_blocks_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."user_blocks_id_seq" OWNER TO "veza";

--
-- TOC entry 4118 (class 0 OID 0)
-- Dependencies: 259
-- Name: user_blocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."user_blocks_id_seq" OWNED BY "public"."user_blocks"."id";


--
-- TOC entry 290 (class 1259 OID 25667)
-- Name: user_blocks_secure; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."user_blocks_secure" (
    "id" bigint NOT NULL,
    "blocker_id" integer NOT NULL,
    "blocked_id" integer NOT NULL,
    "reason" character varying(500),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "no_self_block" CHECK (("blocker_id" <> "blocked_id"))
);


ALTER TABLE "public"."user_blocks_secure" OWNER TO "veza";

--
-- TOC entry 289 (class 1259 OID 25666)
-- Name: user_blocks_secure_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."user_blocks_secure_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."user_blocks_secure_id_seq" OWNER TO "veza";

--
-- TOC entry 4119 (class 0 OID 0)
-- Dependencies: 289
-- Name: user_blocks_secure_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."user_blocks_secure_id_seq" OWNED BY "public"."user_blocks_secure"."id";


--
-- TOC entry 244 (class 1259 OID 24787)
-- Name: user_products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."user_products" (
    "id" integer NOT NULL,
    "user_id" integer NOT NULL,
    "product_id" integer NOT NULL,
    "version" "text" NOT NULL,
    "purchase_date" "date" NOT NULL,
    "warranty_expires" "date" NOT NULL,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."user_products" OWNER TO "postgres";

--
-- TOC entry 243 (class 1259 OID 24786)
-- Name: user_products_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."user_products_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."user_products_id_seq" OWNER TO "postgres";

--
-- TOC entry 4121 (class 0 OID 0)
-- Dependencies: 243
-- Name: user_products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."user_products_id_seq" OWNED BY "public"."user_products"."id";


--
-- TOC entry 266 (class 1259 OID 25097)
-- Name: user_sessions; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."user_sessions" (
    "id" integer NOT NULL,
    "user_id" integer NOT NULL,
    "session_token" character varying(255) NOT NULL,
    "device_info" character varying(255),
    "ip_address" "inet",
    "last_activity" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."user_sessions" OWNER TO "veza";

--
-- TOC entry 4123 (class 0 OID 0)
-- Dependencies: 266
-- Name: TABLE "user_sessions"; Type: COMMENT; Schema: public; Owner: veza
--

COMMENT ON TABLE "public"."user_sessions" IS 'Table des sessions utilisateur actives';


--
-- TOC entry 281 (class 1259 OID 25369)
-- Name: user_sessions_enhanced; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."user_sessions_enhanced" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" integer NOT NULL,
    "token_hash" character varying(128) NOT NULL,
    "ip_address" "inet",
    "user_agent" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_activity" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "is_active" boolean DEFAULT true
);


ALTER TABLE "public"."user_sessions_enhanced" OWNER TO "veza";

--
-- TOC entry 4124 (class 0 OID 0)
-- Dependencies: 281
-- Name: TABLE "user_sessions_enhanced"; Type: COMMENT; Schema: public; Owner: veza
--

COMMENT ON TABLE "public"."user_sessions_enhanced" IS 'Sessions sécurisées';


--
-- TOC entry 265 (class 1259 OID 25096)
-- Name: user_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."user_sessions_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."user_sessions_id_seq" OWNER TO "veza";

--
-- TOC entry 4125 (class 0 OID 0)
-- Dependencies: 265
-- Name: user_sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."user_sessions_id_seq" OWNED BY "public"."user_sessions"."id";


--
-- TOC entry 284 (class 1259 OID 25600)
-- Name: user_sessions_secure; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."user_sessions_secure" (
    "id" "uuid" DEFAULT "public"."uuid_generate_v4"() NOT NULL,
    "user_id" integer NOT NULL,
    "token_hash" character varying(255) NOT NULL,
    "refresh_token_hash" character varying(255),
    "device_info" "jsonb" DEFAULT '{}'::"jsonb",
    "ip_address" "inet" NOT NULL,
    "user_agent" "text",
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '7 days'::interval) NOT NULL,
    "last_used" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."user_sessions_secure" OWNER TO "veza";

--
-- TOC entry 252 (class 1259 OID 24924)
-- Name: users; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."users" (
    "id" integer NOT NULL,
    "username" "text" NOT NULL,
    "email" "text" NOT NULL,
    "password_hash" "text" NOT NULL,
    "first_name" "text" DEFAULT ''::"text",
    "last_name" "text" DEFAULT ''::"text",
    "avatar" "text" DEFAULT ''::"text",
    "bio" "text" DEFAULT ''::"text",
    "role" "text" DEFAULT 'user'::"text",
    "is_active" boolean DEFAULT true,
    "is_verified" boolean DEFAULT false,
    "last_login_at" timestamp without time zone,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "updated_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "status" character varying(20) DEFAULT 'offline'::character varying,
    "last_seen" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "reputation_score" integer DEFAULT 100,
    "is_banned" boolean DEFAULT false,
    "is_muted" boolean DEFAULT false,
    CONSTRAINT "users_role_check" CHECK (("role" = ANY (ARRAY['user'::"text", 'admin'::"text", 'super_admin'::"text", 'moderator'::"text"])))
);


ALTER TABLE "public"."users" OWNER TO "veza";

--
-- TOC entry 220 (class 1259 OID 16391)
-- Name: users_backup; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."users_backup" (
    "id" integer NOT NULL,
    "username" "text" NOT NULL,
    "email" "text" NOT NULL,
    "password_hash" "text" NOT NULL,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."users_backup" OWNER TO "veza";

--
-- TOC entry 270 (class 1259 OID 25207)
-- Name: users_enhanced; Type: TABLE; Schema: public; Owner: veza
--

CREATE TABLE "public"."users_enhanced" (
    "id" integer NOT NULL,
    "username" character varying(50) NOT NULL,
    "email" character varying(255) NOT NULL,
    "password_hash" character varying(255) NOT NULL,
    "role" character varying(20) DEFAULT 'user'::character varying NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "is_banned" boolean DEFAULT false NOT NULL,
    "is_verified" boolean DEFAULT false NOT NULL,
    "status" character varying(20) DEFAULT 'offline'::character varying,
    "status_message" character varying(100),
    "reputation_score" integer DEFAULT 100,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "users_enhanced_role_check" CHECK ((("role")::"text" = ANY ((ARRAY['admin'::character varying, 'moderator'::character varying, 'user'::character varying, 'guest'::character varying])::"text"[]))),
    CONSTRAINT "users_enhanced_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['online'::character varying, 'away'::character varying, 'busy'::character varying, 'invisible'::character varying, 'offline'::character varying])::"text"[])))
);


ALTER TABLE "public"."users_enhanced" OWNER TO "veza";

--
-- TOC entry 4126 (class 0 OID 0)
-- Dependencies: 270
-- Name: TABLE "users_enhanced"; Type: COMMENT; Schema: public; Owner: veza
--

COMMENT ON TABLE "public"."users_enhanced" IS 'Utilisateurs avec sécurité renforcée';


--
-- TOC entry 269 (class 1259 OID 25206)
-- Name: users_enhanced_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."users_enhanced_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."users_enhanced_id_seq" OWNER TO "veza";

--
-- TOC entry 4127 (class 0 OID 0)
-- Dependencies: 269
-- Name: users_enhanced_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."users_enhanced_id_seq" OWNED BY "public"."users_enhanced"."id";


--
-- TOC entry 219 (class 1259 OID 16390)
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."users_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."users_id_seq" OWNER TO "veza";

--
-- TOC entry 4128 (class 0 OID 0)
-- Dependencies: 219
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."users_id_seq" OWNED BY "public"."users_backup"."id";


--
-- TOC entry 251 (class 1259 OID 24923)
-- Name: users_id_seq1; Type: SEQUENCE; Schema: public; Owner: veza
--

CREATE SEQUENCE "public"."users_id_seq1"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."users_id_seq1" OWNER TO "veza";

--
-- TOC entry 4129 (class 0 OID 0)
-- Dependencies: 251
-- Name: users_id_seq1; Type: SEQUENCE OWNED BY; Schema: public; Owner: veza
--

ALTER SEQUENCE "public"."users_id_seq1" OWNED BY "public"."users"."id";


--
-- TOC entry 3537 (class 2604 OID 25123)
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."audit_logs" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."audit_logs_id_seq"'::"regclass");


--
-- TOC entry 3493 (class 2604 OID 24830)
-- Name: categories id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."categories" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."categories_id_seq"'::"regclass");


--
-- TOC entry 3451 (class 2604 OID 16439)
-- Name: files id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."files" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."files_id_seq"'::"regclass");


--
-- TOC entry 3453 (class 2604 OID 16454)
-- Name: internal_documents id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."internal_documents" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."internal_documents_id_seq"'::"regclass");


--
-- TOC entry 3474 (class 2604 OID 24711)
-- Name: listings id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."listings" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."listings_id_seq"'::"regclass");


--
-- TOC entry 3564 (class 2604 OID 25311)
-- Name: message_mentions_enhanced id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_mentions_enhanced" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."message_mentions_enhanced_id_seq"'::"regclass");


--
-- TOC entry 3589 (class 2604 OID 25649)
-- Name: message_mentions_secure id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_mentions_secure" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."message_mentions_secure_id_seq"'::"regclass");


--
-- TOC entry 3523 (class 2604 OID 25011)
-- Name: message_reactions id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_reactions" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."message_reactions_id_seq"'::"regclass");


--
-- TOC entry 3562 (class 2604 OID 25291)
-- Name: message_reactions_enhanced id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_reactions_enhanced" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."message_reactions_enhanced_id_seq"'::"regclass");


--
-- TOC entry 3459 (class 2604 OID 16482)
-- Name: messages id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."messages" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."messages_id_seq"'::"regclass");


--
-- TOC entry 3555 (class 2604 OID 25252)
-- Name: messages_enhanced id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."messages_enhanced" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."messages_enhanced_id_seq"'::"regclass");


--
-- TOC entry 3501 (class 2604 OID 24888)
-- Name: migrations id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."migrations" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."migrations_id_seq"'::"regclass");


--
-- TOC entry 3530 (class 2604 OID 25081)
-- Name: notifications id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."notifications" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."notifications_id_seq"'::"regclass");


--
-- TOC entry 3477 (class 2604 OID 24732)
-- Name: offers id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."offers" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."offers_id_seq"'::"regclass");


--
-- TOC entry 3497 (class 2604 OID 24844)
-- Name: product_documents id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."product_documents" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."product_documents_id_seq"'::"regclass");


--
-- TOC entry 3480 (class 2604 OID 24774)
-- Name: products id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."products" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."products_id_seq1"'::"regclass");


--
-- TOC entry 3518 (class 2604 OID 24959)
-- Name: refresh_tokens id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."refresh_tokens" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."refresh_tokens_id_seq"'::"regclass");


--
-- TOC entry 3527 (class 2604 OID 25057)
-- Name: room_members id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."room_members" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."room_members_id_seq"'::"regclass");


--
-- TOC entry 3455 (class 2604 OID 16469)
-- Name: rooms id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."rooms" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."rooms_id_seq"'::"regclass");


--
-- TOC entry 3520 (class 2604 OID 24988)
-- Name: sanctions id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."sanctions" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."sanctions_id_seq"'::"regclass");


--
-- TOC entry 3575 (class 2604 OID 25391)
-- Name: security_events_enhanced id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."security_events_enhanced" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."security_events_enhanced_id_seq"'::"regclass");


--
-- TOC entry 3585 (class 2604 OID 25626)
-- Name: security_events_secure id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."security_events_secure" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."security_events_secure_id_seq"'::"regclass");


--
-- TOC entry 3469 (class 2604 OID 16535)
-- Name: shared_ressources id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."shared_ressources" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."shared_ressources_id_seq"'::"regclass");


--
-- TOC entry 3473 (class 2604 OID 16553)
-- Name: tags id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."tags" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."tags_id_seq"'::"regclass");


--
-- TOC entry 3466 (class 2604 OID 16502)
-- Name: tracks id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."tracks" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."tracks_id_seq"'::"regclass");


--
-- TOC entry 3525 (class 2604 OID 25032)
-- Name: user_blocks id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."user_blocks_id_seq"'::"regclass");


--
-- TOC entry 3569 (class 2604 OID 25350)
-- Name: user_blocks_enhanced id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks_enhanced" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."user_blocks_enhanced_id_seq"'::"regclass");


--
-- TOC entry 3592 (class 2604 OID 25670)
-- Name: user_blocks_secure id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks_secure" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."user_blocks_secure_id_seq"'::"regclass");


--
-- TOC entry 3491 (class 2604 OID 24790)
-- Name: user_products id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."user_products" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."user_products_id_seq"'::"regclass");


--
-- TOC entry 3533 (class 2604 OID 25100)
-- Name: user_sessions id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_sessions" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."user_sessions_id_seq"'::"regclass");


--
-- TOC entry 3503 (class 2604 OID 24927)
-- Name: users id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."users" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."users_id_seq1"'::"regclass");


--
-- TOC entry 3449 (class 2604 OID 16394)
-- Name: users_backup id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."users_backup" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."users_id_seq"'::"regclass");


--
-- TOC entry 3539 (class 2604 OID 25210)
-- Name: users_enhanced id; Type: DEFAULT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."users_enhanced" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."users_enhanced_id_seq"'::"regclass");


--
-- TOC entry 4039 (class 0 OID 25120)
-- Dependencies: 268
-- Data for Name: audit_logs; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4017 (class 0 OID 24827)
-- Dependencies: 246
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: veza
--

INSERT INTO "public"."categories" ("id", "name", "description", "created_at", "updated_at") VALUES (1, 'Microphones', 'Microphones et accessoires', '2025-06-04 10:49:45.716743', '2025-06-04 10:49:45.716743');
INSERT INTO "public"."categories" ("id", "name", "description", "created_at", "updated_at") VALUES (2, 'Interfaces Audio', 'Cartes son et interfaces audio', '2025-06-04 10:49:45.716743', '2025-06-04 10:49:45.716743');
INSERT INTO "public"."categories" ("id", "name", "description", "created_at", "updated_at") VALUES (3, 'Casques', 'Casques et écouteurs', '2025-06-04 10:49:45.716743', '2025-06-04 10:49:45.716743');
INSERT INTO "public"."categories" ("id", "name", "description", "created_at", "updated_at") VALUES (4, 'Enceintes', 'Enceintes de monitoring et haut-parleurs', '2025-06-04 10:49:45.716743', '2025-06-04 10:49:45.716743');
INSERT INTO "public"."categories" ("id", "name", "description", "created_at", "updated_at") VALUES (5, 'Contrôleurs', 'Contrôleurs MIDI et surfaces de contrôle', '2025-06-04 10:49:45.716743', '2025-06-04 10:49:45.716743');
INSERT INTO "public"."categories" ("id", "name", "description", "created_at", "updated_at") VALUES (6, 'Tables de mixage', 'Consoles de mixage et tables', '2025-06-04 10:49:45.716743', '2025-06-04 10:49:45.716743');
INSERT INTO "public"."categories" ("id", "name", "description", "created_at", "updated_at") VALUES (7, 'Traitement', 'Égaliseurs, compresseurs et effets', '2025-06-04 10:49:45.716743', '2025-06-04 10:49:45.716743');
INSERT INTO "public"."categories" ("id", "name", "description", "created_at", "updated_at") VALUES (8, 'Câbles', 'Câbles et connectique', '2025-06-04 10:49:45.716743', '2025-06-04 10:49:45.716743');
INSERT INTO "public"."categories" ("id", "name", "description", "created_at", "updated_at") VALUES (9, 'Accessoires', 'Pieds, supports et autres accessoires', '2025-06-04 10:49:45.716743', '2025-06-04 10:49:45.716743');


--
-- TOC entry 3993 (class 0 OID 16436)
-- Dependencies: 222
-- Data for Name: files; Type: TABLE DATA; Schema: public; Owner: veza
--

INSERT INTO "public"."files" ("id", "product_id", "filename", "url", "type", "uploaded_at") VALUES (1, 1, 'test_upload.txt', '/files/1_1747129598_test_upload.txt', 'test', '2025-05-13 09:46:38.538325');


--
-- TOC entry 3995 (class 0 OID 16451)
-- Dependencies: 224
-- Data for Name: internal_documents; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4009 (class 0 OID 24708)
-- Dependencies: 238
-- Data for Name: listings; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."listings" ("id", "user_id", "product_id", "description", "state", "price", "exchange_for", "images", "status", "created_at") VALUES (3, 10, 8, 'Exemple test', 'bon état', 100, 'autre produit', '{https://via.placeholder.com/150}', 'open', '2025-06-03 16:18:01.999698');
INSERT INTO "public"."listings" ("id", "user_id", "product_id", "description", "state", "price", "exchange_for", "images", "status", "created_at") VALUES (6, 8, 8, 'test ', 'neuf', 103, 'hobotnica', '{"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAB30AAAOPCAIAAABAa0x+AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAN0jSURBVHhe7P2LlxTVof9/P2t913r+gN965Dbj97tyzvP7/R4QEBlmvBFBFCHneI75kRxN8o1Rc/MSPZqowRjUKMZ4Fy+YYEQx4gUUFRFEUTgiHOWmCIIg90FA7jDcZmBgnj1dPT17PtXVXVNTvanpeu/1Wi6c3lW9a1fVrqpPV1f/v06t+R4AAAAAAEDanNKzGgBQIuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjzZ3lZQe6nnaWtCFI936DZVoHKquHSTOCyIQOdOt7nrQhSJfTzpZpS65XjbQhSMJXK8rSKT1rZJMotW59BkobCpBpHejWtx3NQwRmzJE+d6Db6WGPEaf0OlOmLbUuvc6UNiBVevS/QDYJByqqhkozOqHhslAOhD9AdO19lkxbauFHkh79h8i0DlRUXSjNCOL+tKRr73OkDUiVrr3PlU2i9MJeG54UvtYCAGJD7lwEuXNE5M5IMHJnQe5cauTOgtw55cidoyJ3boPcOTJy55Qjdxa+1gIAYkPuXAS5c0TkzkgwcmdB7lxq5M6C3DnlyJ2jIndug9w5MnLnlCN3Fr7WAgBiQ+5cBLlzROTOSDByZ0HuXGrkzoLcOeXInaMid26D3DkycueUI3cWvtYCAGJD7lwEuXNE5M5IMHJnQe5cauTOgtw55cidoyJ3boPcOTJy55Qjdxa+1gIAYkPuXAS5c0TkzkgwcmdB7lxq5M6C3DnlyJ2jIndug9w5MnLnlCN3Fr7WAgBiQ+5cBLlzROTOSDByZ0HuXGrkzoLcOeXInaMid26D3DkycueUI3cWvtYCAGJD7lwEuXNE5M5IMHJnQe5cauTOgtw55cidoyJ3boPcOTJy55Qjdxa+1gIAYkPuXAS5c0TkzkgwcmdB7lxq5M6C3DnlyJ2jIndug9w5MnLnlCN3Fr7WAgBio7lz5YCLnAudAFYP901bctqGYDKhC6HDU9PJOm3pSRsCJXu1oizJ9uBCez7q0Gkd4JOY0tM+d6AdxwjftKUnbUC6nJxD/3BtRickC+VCeYwkyd7kZEInOO6nmtmvfZtEyUkbEkUiEgBAjDR3BgAAAAAASAOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5c2y69KpxrFvf70obkCpdTjtTNomSO+1MaUOQ7v3O12lLr6LqAmlGkC69XHdd1z4DpQ2IXUX/C6TbHaioGirNQKqchMGk99nShiBd+5wr0zpwavVwaUZe7K1lyWyc0uelF/a0BGXJ7NS+TaLkKvoPkWYEGC4TOtC1zzm+ZuTXtfc5Mm3pJXpvlYgEABAjcufYSM860K3PudIGpMopPWtkkyi1Lj2rpQ1Bup0+SKZ1oEfYK4GTsLd27c3eWnLmUlC63YGKqgulGUgV2R4c6Br60r1L73NkWgcqw+XOPc5gby1DXU87S/q89GqkDUiViqqhvk2i5Hqccb40I7/q4TKhA11CfzDZpZf7vTXsRcRJIU0FAMSI3Dk20rMOkDunHLmzIHdOOXJnuCfbgwPkzpGxt5YauTMcI3cW5M6RSVMBADEid46N9KwD5M4pR+4syJ1TjtwZ7sn24AC5c2TsraVG7gzHyJ0FuXNk0lQAQIzInWMjPesAuXPKkTsLcueUI3eGe7I9OEDuHBl7a6mRO8MxcmdB7hyZNBUAECNy59hIzzpA7pxy5M6C3DnlyJ3hnmwPDpA7R8beWmrkznCM3FmQO0cmTQUAxIjcOTbSsw6QO6ccubMgd045cme4J9uDA+TOkbG3lhq5MxwjdxbkzpFJUwEAMSJ3jo30rAPkzilH7izInVOO3BnuyfbgALlzZOytpUbuDMfInQW5c2TSVABAjMidYyM96wC5c8qROwty55Qjd4Z7sj04QO4cGXtrqZE7wzFyZ0HuHJk0FQAQI3Ln2FQOGOrYqTXDpA1IlwHDZJMotVOrL9I2BBlwMvaIal8zAsiEDpjLD2kD4lc9XLrdgVNrWLOpVjngItkkSu3UmrDjcKXzY4QhbQh2MvZWxuFSc7/JhT8tQZnSTaL0wh/3ZUInwl8buj54mcOlrw0JIhEJACBG5M4AAAAAACCNJCIBAMSI3BkAAAAAAKSRRCQAgBiROwMAAAAAgDSSiAQAECNyZwAAAAAAkEYSkQAAYkTuDAAAAAAA0kgiEgBAjMidAQAAAABAGklEAgCIEbkzAAAAAABII4lIAAAxIncGAAAAAABpJBEJACBG5M5AoMrqYV17n+NYjzOGSDOQKt1OP082iZLrc660AUiO/2fg2XO/18WxIed8V5qBFKkeroNk6XXvN1ibASTDPUN6yQjpQM8zh0ozkB6VAy6SEdIBiUgAADEidwYCmfMe2WEc6N5vkDQDqdK199mySZRcrxppA5Acvzqvqun7/8Ox7597tjQDKVI9XAfJ0uvWd6A2A0iGVy76nzJCOtDnrAulGUiPygFDZYQEAHRq5M5AIHJnuEfuDNjIneEauTNgIXeGY+TOAFBmyJ2BQOTOcI/cGbCRO8M1cmfAQu4Mx8idAaDMkDsDgcid4R65M2Ajd4Zr5M6AhdwZjpE7A0CZIXcGApE7wz1yZ8BG7gzXyJ0BC7kzHCN3BoAyQ+4MBCJ3hnvkzoCN3BmukTsDFnJnOEbuDABlhtwZCETuDPfInQEbuTNcI3cGLOTOcIzcGQDKDLkzEIjcGe6ROwM2cme4Ru4MWMid4Ri5MwCUGXJnIFBl9fAe/Yc4VjngImkGUqWi6kLZJByQNgDJUXP2+dcP6udYXyKPdJMR0gEz8ksbgIT4t4HnyAjpwD+dOUyagfQ4KddfEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gx0Vt36Duza5xyXuvUZKG0I0vsHt37voYWO/V/DfiHNAICS6trnXBknS6173/OkDUG69xsk0zpwas1waQYAlEjlgItkCHKgoupCaUYQmdABM+xLGxCSRCQAgBiROwOdVZfTzpT9udS69DpT2hCk/8/+/JPJRx3r+e//Kc0AgJI6pVeNjJOl1rX32dKGIF37DJRpHSB3BuBMRdVQGYIcqOg/RJoRRCZ0oGufc6UNCEl6EgAQI3JnoLMidxbkzgAcI3cW5M4AnCF3FuTOkUlPAgBiRO4MdFbkzoLcGYBj5M6C3BmAM+TOgtw5MulJAECMyJ2BzorcWZA7A3CM3FmQOwNwhtxZkDtHJj0JAIgRuTPQWZE7C3JnAI6ROwtyZwDOkDsLcufIpCcBADEidwY6K3JnQe4MwDFyZ0HuDMAZcmdB7hyZ9CQAIEbkzkBnRe4syJ0BOEbuLMidAThD7izInSOTngQAxIjcGeisyJ0FuTMAx8idBbkzAGfInQW5c2TSkwCAGJE7A51VjzOG9Oh3vlNnhD3V/j8v+vmZv37SsX8a/CNpBgCUVI8zfONkqfW/QNoQpKLqAp229KQNAFA6ldXDZAhyoHLARdKMIDKhAxWhDxAQEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGKkuXP3foMc63HG+dKGIBVVQ2VaByqrh0szAKCkZBRyoKL/BdKGID3OGCLTOiBtAIDSqaweJkOQA5UDLpJmBJEJHejRf4i0AQDKjEQkAIAYae4sLzvQ9bSzpA1BuvcbLNM6YC4/pBkAUFIyCjnQre9AaUOQrn3OlWkdOLWGz/8AOFJRNVSGIAdCf/g3XCZ0IPwBAgA6KRn3AAAxIncugtwZgGMyCjlA7gwAHnJnQe4MoOzJuAcAiBG5cxHkzgAck1HIAXJnAPCQOwtyZwBlT8Y9AECMyJ2LIHcG4JiMQg6QOwOAh9xZkDsDKHsy7gEAYkTuXAS5MwDHZBRygNwZADzkzoLcGUDZk3EPABAjcuciyJ0BOCajkAPkzgDgIXcW5M4Ayp6MewCAGJE7F0HuDMAxGYUcIHcGAA+5syB3BlD2ZNwDAMSI3LkIcmcAjsko5AC5MwB4yJ0FuTOAsifjHgAgRpo79zh9kGtnnC9tCGKuBLr3G+TYqdXkHQCc0kGy9EJHHt/r0X+IDJIOSBsAoHQqq4fJCOlA5YCwdznI8OhA+AMEAHRSEpEAAGKkuTMAAAAAAEAaSEQCAIgRuTMAAAAAAEgjiUgAADEidwYAAAAAAGkkEQkAIEbkzgAAAAAAII0kIgEAxIjcGQAAAAAApJFEJACAGJE7AwAAAACANJKIBAAQI3JnAAAAAACQRhKRAABiRO4MAAAAAADSSCISAECMNHfuccb5rvUfIm0IUlE1VKctvcrq4dIMACgpGYUcqKi6UNoQpKL/BTKtA9IGACidyuphMgQ5YN5UmhFEJnQg/AECADopiUgAADHS3FledqDraWdJG4J07zdYpnUg/JUAAMRCRiEHuvUdKG0I0rXPuTKtA6fW8PkfAEcqqobKEORARf8LpBkBhsuEDoQ/QABAJyXjHgAgRuTORZA7A3BMRiEHyJ0BwEPuLMidAZQ9GfcAADEidy6C3BmAYzIKOUDuDAAecmdB7gyg7Mm4BwCIEblzEeTOAByTUcgBcmcA8JA7C3JnAGVPxj0AQIzInYsgdwbgmIxCDpA7A4CH3FmQOwMoezLuAQBiRO5cBLkzAMdkFHKA3BkAPOTOgtwZQNmTcQ8AECNy5yLInQE4JqOQA+TOAOAhdxbkzgDKnox7AIAYkTsXQe4MwDEZhRwgdwYAD7mzIHcGUPZk3AMAxEhz5y59znWsW9/zpA1BepwxRKZ1gNwZgGMyCjnQvd9gaUOQbqcPkmkdkDYAQOlUDrhIhiAHKqqGSjOCyIQOhD9AAEAnJREJACBGmjsDAAAAAACkgUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNw5FSr6X9DjjCFO9b9A2hCkcsBFOm3pnVozXJoBAKXzv87+96orH3Cs57/fIM0IYkZsGSRLreKMsMcIAOi4/++Qn8oI6cA/DbpMmhFERkgHzKWBtAFIM4lIAAAxIndOhS6nnS0rvuR61UgbgnTvN1inLb3K6mHSDAAonX8adNlPJh91bNDIKdKMIKf0OlMGyVLr0utMaQMAlE6/H98lI6QDvS65UZoR5JSeNTJIllrX3udIG4A0kx0EABAjcudUIHcW5M4AXCJ3FuTOAFwidxbkzoBNdhAAQIzInVOB3FmQOwNwidxZkDsDcIncWZA7AzbZQQAAMSJ3TgVyZ0HuDMAlcmdB7gzAJXJnQe4M2GQHAQDEiNw5FcidBbkzAJfInQW5MwCXyJ0FuTNgkx0EABAjcudUIHcW5M4AXCJ3FuTOAFwidxbkzoBNdhAAQIzInVOB3FmQOwNwidxZkDsDcIncWZA7AzbZQQAAMSJ3TgVyZ0HuDMAlcmdB7gzAJXJnQe4M2GQHAQDEiNw5Fbr1/a45v3Sqz7nShiA9zhii05beqdXDpRkAUDrf+e4P/vWRJY6defWT0owgXfsMlEGy1Lr1GShtAIDSOe37v5UR0oH/+3u/kmYEMafNMkiWWre+50kbgDSTiAQAECNyZwAAAAAAkEYSkQAAYkTuDAAAAAAA0kgiEgBAjMidAQAAAABAGklEAgCIEbkzAAAAAABII4lIAAAxIncGAAAAAABpJBEJACBG5M4AAAAAACCNJCIBAMSI3BkAAAAAAKSRRCQAgBiROwMAAAAAgDSSiAQAECNy51SorB7mnrQhUPVwmdABbQMAlNL/qhledfYQx3qeeZE0I8g/D/rxP5//v136p8E/ljYAQOn885nDZIR04Ds1w6UZQf558E9kkCy1fxp0qbQBSDOJSAAAMSJ3ToUup50tK77ketVIG4J07zdYpy09omcALp1+1gVN3/8fjj174XekGUF++Py3P5l81KUfPr9d2gAApfPz86pkhHTg3889W5oR5LKX6mSQLLV/e3yFtAFIM7lUBADEiNw5FcidBbkzAJfInQW5MwCXyJ0FuTNgk0tFAECMyJ1TgdxZkDsDcIncWZA7A3CJ3FmQOwM2uVQEAMSI3DkVyJ0FuTMAl8idBbkzAJfInQW5M2CTS0UAQIzInVOB3FmQOwNwidxZkDsDcIncWZA7Aza5VAQAxIjcORXInQW5MwCXyJ0FuTMAl8idBbkzYJNLRQBAjMidU4HcWZA7A3CJ3FmQOwNwidxZkDsDNrlUBADEiNw5FcidBbkzAJfInQW5MwCXyJ0FuTNgk0tFAECMyJ1ToVvfgV17n+PWudKGID3OGOKbtuQqq4dLMwCgdE47a+jif/k/HLvr/F7SjCDD7pt38ZhlLg3/y3xpAwCUzoiBZ8kI6cAF53xXmhHkXx5eLINkqQ0ZNV3aAKSZRCQAgBiROwMAAAAAgDSSiAQAECNyZwAAAAAAkEYSkQAAYkTuDAAAAAAA0kgiEgBAjMidAQAAAABAGklEAgCIEbkzAAAAAABII4lIAAAxIncGAAAAAABpJBEJACBG5M4AAAAAACCNJCIBAMSI3BkAAAAAAKSRRCQAgBiRO8emcsBFrlUPkzYACEN3JQfYWx2oHq7dXnqn1gzXZgAoir21HFUOGCZ97oC0AUAY5rxUdiUHpA2JIhEJACBG5M6xkZ51oFvf86QNAMI4pWeN7E2l1q3PQGkDYlfRf4h0uwMVVUOlGQCK6tH/AtmVHGBvLbWuvc+SPi+1Lr3OlDYACKNr73Nlbyq9GmlDovhaCwCIDblzbKRnHSB3BqIhdy5L5M5AZ0HuXJbInYHOgtxZ+FoLAIgNuXNspGcdIHcGoiF3LkvkzkBnQe5clsidgc6C3Fn4WgsAiA25c2ykZx0gdwaiIXcuS+TOQGdB7lyWyJ2BzoLcWfhaCwCIDblzbKRnHSB3BqIhdy5L5M5AZ0HuXJbInYHOgtxZ+FoLAIgNuXNspGcdIHcGoiF3LkvkzkBnQe5clsidgc6C3Fn4WgsAiA25c2ykZx0gdwaiIXcuS+TOQGdB7lyWyJ2BzoLcWfhaCwCIDblzbKRnHSB3BqIhdy5L5M5AZ0HuXJbInYHOgtxZ+FoLAIgNuXNspGcdIHcGoiF3LkvkzkBnQe5clsidgc6C3Fn4WgsAiA25MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNw5Fbr2PvuUXjUudel1prQhSPd+g2VaByqrh0szAKB0KquHySjkQPfTz5NmBOly2lkybamZd5Q2AEDp9Oh/gYxCDlRUDZVmBDml15kybal17X2OtAFIM4lIAAAxIndOhS6nnS0rvuR61UgbgjTnzjJt6VVWD5NmAEDpNOfOvoGo1LqFzp2bIw/f5CUV/rNJAOi4Hv2HyCjkQEXVhdKMIKf0rJFpS43cGbDJDgIAiBG5cyqQOwtyZwAukTsLcmcALpE7C3JnwCY7CAAgRuTOqUDuLMidAbhE7izInQG4RO4syJ0Bm+wgAIAYkTunArmzIHcG4BK5syB3BuASubMgdwZssoMAAGJE7pwK5M6C3BmAS+TOgtwZgEvkzoLcGbDJDgIAiBG5cyqQOwtyZwAukTsLcmcALpE7C3JnwCY7CAAgRuTOqUDuLMidAbhE7izInQG4RO4syJ0Bm+wgAIAYkTungjm5zJzRuhM+U8jkzjp5qZE7A3ApkzvrQFRq3UPnzl1OO0umLTXzjtIGACidHv0vkFHIgYqqodKMIJkP/3TykiJ3BmwSkQAAYkTuDAAAAAAA0kgiEgBAjMidAQAAAABAGklEAgCIEbkzAAAAAABII4lIAAAxIncGAAAAAABpJBEJACBG5M4AAAAAACCNJCIBAMSI3BkAAAAAAKSRRCQAgBiROwMAAAAAgDSSiAQAECNyZwAAAAAAkEYSkQAAYkTuDAAAAAAA0kgiEgBAjDR3PqVXjWNde58tbQjSvd9gmdaByuph0gykR+WAi2R7cKBHv8HSDKRK1z7nnNKzxrFufb8rzQgy7C/zLpu437H/efa/STOQHhX9L5BB0oHKqqHSDKRHRdVQGSEdCDkI/6+z/12GRweG3DFdmoFUMRunjJAOnFo9XJqB9KgcMFS2Bxd8KQkAIC6+3NlXo9S6nnaWtCFIc+7sm7zUyJ3TrDl39m0Spda93yBpBlKla++zZZNwoFvfgdKMIP/y0MKfTD7qGLlzmvXoP0Q2Vwcqqi6UZiA9MrmzbhKlFnIQ/l9n/7sMjw5cePcsaQZSxWycsrk6QO6cZs25s2+TAAB0XuTORZA7pxm5M9wjd/Yjd04zcmc4Ru4syJ1TjtwZjpE7A0CZIXcugtw5zcid4R65sx+5c5qRO8MxcmdB7pxy5M5wjNwZAMoMuXMR5M5pRu4M98id/cid04zcGY6ROwty55Qjd4Zj5M4AUGbInYsgd04zcme4R+7sR+6cZuTOcIzcWZA7pxy5MxwjdwaAMkPuXAS5c5qRO8M9cmc/cuc0I3eGY+TOgtw55cid4Ri5MwCUGXLnIsid04zcGe6RO/uRO6cZuTMcI3cW5M4pR+4Mx8idAaDMkDsXQe6cZuTOcI/c2Y/cOc3IneEYubMgd045cmc4Ru4MAGVGc+fKARc5FzrYrR7um7bkTq3hvCfVZHtwgVPtdKusHlZZdaFbQ08N/QHbP5//k/9z6JWOnVrzL9IMpAmHfrhlzjZ1kCy9sCfD/yLDowP/NPhHvmYgRZpPS3yDZKlJG5A2sj04IBEJACBGmjsDAAAAAACkgUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDESHNnedmBrqedJW0I0r3fYJnWgcrqYdKMIDKhA936nidtQKp0Oe1M2SRKrUuvM6UNQXr0v0CmdaBiwFBpRicly+VAt74DpQ1BuvY5V6Z14NSa4dKMvCr6D5EJHaioKpOtDtEcuOT/3fT9/+HSJ9/7/0gbgnTtM1A2VwdC7q1JZnZqWSgHKvpfIM0IMFwmdKAdB4jeZ8m0pRb+tARl6XvnnisjpAO/PK9KmhFENlcHzEmatAEhSU8CAGJE7lwEuTMSi9xZkDtHRu4cGblzypE7C3LnaMidoyF3TjlyZ0HuHJn0JAAgRuTORZA7I7HInQW5c2TkzpGRO6ccubMgd46G3DkacueUI3cW5M6RSU8CAGJE7lwEuTMSi9xZkDtHRu4cGblzypE7C3LnaMidoyF3TjlyZ0HuHJn0JAAgRuTORZA7I7HInQW5c2TkzpGRO6ccubMgd46G3DkacueUI3cW5M6RSU8CAGJE7lwEuTMSi9xZkDtHRu4cGblzypE7C3LnaMidoyF3TjlyZ0HuHJn0JAAgRuTORZA7I7HInQW5c2TkzpGRO6ccubMgd46G3DkacueUI3cW5M6RSU8CAGJE7lwEuTMSi9xZkDtHRu4cGblzypE7C3LnaMidoyF3TjlyZ0HuHJn0JAAgRuTORZA7I7HInQW5c2TkzpGRO6ccubMgd46G3DkacueUI3cW5M6RSU8CAGKkuXPlgItcCx3snlo9XKctPW1DMJnQhfBdh3JUOWCYbhKlJ20IdHL21k6fd3hkuVwIPZiYmjpt6UkbArHVwblzzx488JxBLlWfPUTaECTRe2uinYyRpDrsSCITuhD+AJHk0xKUo38+c5iMkA7832eG3epkW3WBa8OoJCIBAMRIc2cAAAAAAIA0kIgEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYae7ctfc5jnXrO1DaEKRH/yEyrQOV1cOkGUFkQge69ztf2oBUMfuObBKl1q3PudKGID2qLpRpHagccJE0I4hM6ED30wdJGwqQaR3o3i9s87qffp5M64C0IUhFsrc6lKWufXSTKDWzD0obgphhR6Z14NSa4dKMvCqqhsqEDoTcW001mdAB0yHSjCAyoQPhDxBJPi1BWTpJe+uF0owgMqED4Q8Q3RJ8OndSSEQCAIiR5s7ysgNdTztL2hCke7/BMq0D4XNnmdCBbn3DnlugLHU57UzZJEqtS68zpQ1BevS/QKZ1oGJA2Ov2U3rWyLSl1q1P2A/YDJnWgfCf/3Xtc65M60DYJKv/EJnQgfBpEcrSKb1cDyZde58tbQjStc9AmdaBkHvryTlGhNtbTTWZ0IGK/hdIMwIMlwkdaMcBovdZMm2phT8tQVk6SXvrEGlGEJnQAXOSJm0I0rW3+9O5GmlDovhaCwCIDblzEeTOSCxyZ0HuHBm5c2TkzilH7izInaMhd46G3DnlyJ0FuXNkvtYCAGJD7lwEuTMSi9xZkDtHRu4cGblzypE7C3LnaMidoyF3TjlyZ0HuHJmvtQCA2JA7F0HujMQidxbkzpGRO0dG7pxy5M6C3DkacudoyJ1TjtxZkDtH5mstACA25M5FkDsjscidBblzZOTOkZE7pxy5syB3jobcORpy55QjdxbkzpH5WgsAiA25cxHkzkgscmdB7hwZuXNk5M4pR+4syJ2jIXeOhtw55cidBblzZL7WAgBiQ+5cBLkzEovcWZA7R0buHBm5c8qROwty52jInaMhd045cmdB7hyZr7UAgNiQOxdB7ozEIncW5M6RkTtHRu6ccuTOgtw5GnLnaMidU47cWZA7R+ZrLQAgNpo7Vw4Y5lroYPfU6uE6bemdWu1rRgCZ0IXqUFd3KFeV1RfpJlFqofdWs3HqtA6E3iN0Qgfas7fqtA4kfByWNgQ6KccIxuFUk+3BheqLpA1BTso4LG0Ilui9VSZ0IGReb8iEToRuW7VM6IK0ASlzUka5BO+t4Uc59ta2JCIBAMRIc2cAAAAAAIA0kIgEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTunQre+3+3a+xyXuvU5V9oQpMcZQ2RaB06tHi7NQKp07XOubBKl1v30wdIGpEpl9XDZJBzoccb50owgQ0fP/peHFrk0dPQcaQNSpaJqqGyuDlQOuEiagfSoqLpQtgcHKkJvcsP/Ml8GyVIb/Ie3pA1IlW6nD5LNteRCXxueFBKRAABiRO6cCl1OO1tWfMn1qpE2BOneb7BOW3qV1cOkGUiVU3rWyCZRat36DJQ2IFXMmCObhAPdTj9PmhHkh89/+5PJR1364fPbpQ1IlR79L5DN1YGKqqHSDKRHj/5DZHtwoKLqQmlGkMteqpNBstT+7fEV0gakStfe58rmWnphrw1PCl9rAQCxIXdOBXJnQe6ccuTOcIzcWZA7pxy5MxwjdxbkzilH7ix8rQUAxIbcORXInQW5c8qRO8MxcmdB7pxy5M5wjNxZkDunHLmz8LUWABAbcudUIHcW5M4pR+4Mx8idBblzypE7wzFyZ0HunHLkzsLXWgBAbMidU4HcWZA7pxy5MxwjdxbkzilH7gzHyJ0FuXPKkTsLX2sBALEhd04FcmdB7pxy5M5wjNxZkDunHLkzHCN3FuTOKUfuLHytBQDEhtw5FcidBblzypE7wzFyZ0HunHLkznCM3FmQO6ccubPwtRYAEBty51QgdxbkzilH7gzHyJ0FuXPKkTvDMXJnQe6ccuTOwtdaAEBsyJ1TwVzg9eh3vlNnDJE2BKkcMFSnLb1Ta4ZLM5AqZvuUTaLUKvqHvfhEmRoum4QD4VO2/pf/ecDPH3Gp/8/ukzYgVSqrh8nm6gAfOadZ5YBEb3JVVz4gg2Spnf7jO6UNSJWKquReG54UEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTvHpkf/IY5VVg2VNgAIQ3YlByrYW0uvsnqYdLsDp1YPl2YAKOqk7K2V7K0lVlF1gfR5qVWYQdjXDABFVVRdKHuTA9KGRJGIBAAQI3Ln2EjPOtCt73nSBgBhnNKzRvamUuvWZ6C0AbGr6D9Eut0BPlEAIujR/wLZlRxgby21rr3Pkj4vtS69zpQ2AAija+9zZW8qvRppQ6L4WgsAiA25c2ykZx0gdwaiIXcuS+TOQGdB7lyWyJ2BzoLcWfhaCwCIDblzbKRnHSB3BqIhdy5L5M5AZ0HuXJbInYHOgtxZ+FoLAIgNuXNspGcdIHcGoiF3LkvkzkBnQe5clsidgc6C3Fn4WgsAiA25c2ykZx0gdwaiIXcuS+TOQGdB7lyWyJ2BzoLcWfhaCwCIDblzbKRnHSB3BqIhdy5L5M5AZ0HuXJbInYHOgtxZ+FoLAIgNuXNspGcdIHcGoiF3LkvkzkBnQe5clsidgc6C3Fn4WgsAiA25c2ykZx0gdwaiIXcuS+TOQGdB7lyWyJ2BzoLcWfhaCwCIDblzbLr2Psex7v3OlzYACKNrn3Nlbyq17qcPljYgdhVVF0q3O1A54CJpBoCiKqqGyq7kAHtrqXXr+13p81Lr1udcaQOAMLqdfp7sTSWX7L1VIhIAQIzInQEAAAAAQBpJRAIAiBG5MwAAAAAASCOJSAAAMSJ3BgAAAAAAaSQRCQAgRuTOAAAAAAAgjSQiAQDEiNwZAAAAAACkkUQkAIAYkTsDAAAAAIA0kogEABAjcmcAAAAAAJBGEpEAAGJE7gwAAAAAANJIIhIAQIzInYHOqrJmeGW1WzXDpQ0F6LSlJw0AgFKTUciF8OOwTOiEtgEASkmGIAekAQXIhG5IGxCSRCQAgBiROwOdVZfTzpT9udS69DpT2hCkR/8LZFoHKgYMlWYAQEmd0qtGBqJS69r7bGlDkK59Bsq0Dpzano8nAaAjKqqGyhDkQEX/IdKMIDKhA137nCttQEjSkwCAGJE7A50VubMgdwbgGLmzIHcG4Ay5syB3jkx6EgAQI3JnoLMidxbkzgAcI3cW5M4AnCF3FuTOkUlPAgBiRO4MdFbkzoLcGYBj5M6C3BmAM+TOgtw5MulJAECMyJ2BzorcWZA7A3CM3FmQOwNwhtxZkDtHJj0JAIgRuTPQWZE7C3JnAI6ROwtyZwDOkDsLcufIpCcBADEidwY6K3JnQe4MwDFyZ0HuDMAZcmdB7hyZ9CQAIEbkzkBnRe4syJ0BOEbuLMidAThD7izInSOTngQAxIjcGeiszMlll95nuxT+dLZH/wtlWgcqB1wkzQCAkurS+xwZiEqte9/vShuCdDt9kEzrALkzAGfMiZ8MQQ5UVF0ozQgiEzrQ7fTzpA0ISSISAECMyJ0BAAAAAEAaSUQCAIgRuTMAAAAAAEgjiUgAADEidwYAAAAAAGkkEQkAIEbkzgAAAAAAII0kIgEAxIjcGQAAAAAApJFEJACAGJE7AwAAAACANJKIBAAQI3JnAAAAAACQRhKRAABiRO4MAAAAAADSSCISAECMyJ1jUzngIteqh0kbglQOGKbTlp60IUhl9XCZ0AFpQyd1MlZr2E3u1JOzWodrM5Aqyd7qZEIXyuIYkXCyUC6EX63VrFY4lehNjgOECn1Gl2gnY7VWl8NxH0IiEgBAjMidYyM960C3vudJG4J0Oe1smbbketVIG4J07zdYpy298jgt63LambJcpdal15nShiA9+l8g0zpQMWCoNAOpUtF/iGwSDlRUhdrqzJgjEzrQ7fSwx4hTeiV3MEk4c7CTRSu1rr3PljYE6dpnoEzrAJ//pVnX3mfJ9lBq7TktOSkHiAulGUFO6el+JDlH2tAZmUOwLJcD5mRDmhFEJnSga59zpQ0ISXoSABAjcufYSM86QO4cGblzNOTOSDJyZ0Hu7AC5syB3TjNyZ0HuXGrkzoLcOTLpSQBAjMidYyM96wC5c2TkztGQOyPJyJ0FubMD5M6C3DnNyJ0FuXOpkTsLcufIpCcBADEid46N9KwD5M5+19w66q13Z329bsP+ugPHGhubWor5t/mL+bt51dQhd44mVbnzz266Y8qMD9duqK07cFC2pQOHDm/6Ztu7c+bfcMcDMhVOInJnQe7sALmzIHc2Lr7yxgmvTVu6YvXuvfuP1DdkDx5NTY3Hjx84eMgcVqbNmluWhw9yZ0HuXGrkzoLcOTLpSQBAjMidYyM9Kx5++tmGo0ezVx5NTebC47qRd0kdw/zRvJSt1J5y4sSJQ4ePbN2+8+MFn9335Piaiy+32xaUO69auz47vVW+WPGVVIuiV83b73+UnaNVtu3Yddl1t9ltiyV3Pn3wv7742ls7d+8x/ZB9p+Bi6uzdXzdp2vvSS4XdeNdDBw4dzs6i/cVceZq1E29S6Th3NtvwUWsbnrfwc2mPrfPmzj0Hj3hqwqQdu0JtS6bsqzvQ3m0JkZmtLtvvZhQ9dNjslfarnTF3HnHltVu/3ZFdpEyZ+PpUqRNZZ8mdv16/Kbvw+VZrmAqFN4ySIncWac6dzeHjob/945tt20Oeiuzas/flt2aW0+GD3Fk4y53nfrIwu2EFX2IIcufIyJ3LkvQkACBG5M6xkZ4Vpc6dpZgL7ykzPsxdzLQrd967v+6aW0dJzfYa/uOfm0uv7BytUorc+dG/PWfanH2D9pS6AwefmzTVXCja7QnSwdw5V8yl5sbNW2+9d4zMPwJyZ9Hx3NmsZbN2QibOdtm1Z+89Y56RuSF25M7tQu7sALmzSG3ubA7rkQ8f9z31nMytkyJ3FuTOpUbuLMidI5OeBADEiNw5NtKzwnHubIq5+Fm9buOl14w0bWtX7mwmfGlKR4OPh//67NGjx7JztEq8ufPAiy+dv3BJhMu8XDHTfvblqkt+/lu7SXndGFPu7JVjjY3vfDA3ZOQdhNxZdDB3fvSZiR1ZxfUNDRNemybzRLzInduF3NkBcmeRwtzZHMpfffu9vOc8IUsspwRJQO4syJ1LjdxZkDtHJj0JAIgRuXNspGeF+9zZK1+s/NpcybQrdzZlzfqNZ33vB1K5XT5Z3JoC2CXG3Hn4j676ctXXeUPnw0eOfL1uw/RZcyZPne4x/zZ/MX/P1mhb1tdu+dlNd9it8os3dzbFtPyjT5d05DqT3Fl0JHf+w/1P7q87mF22lmLW0b66A0tXrH5z5pwpMz70vDtn/toNtfUNrY/szBXzxyeff1XmjBiFzJ3tkS3kFXhknT13NgOyGZaz793UZBpjmiTzKQVy58jInRPFHMTNoTzvqUhDw9FN32z74OMFucPH2+9/ZDbmw0fqszWs0vFTgiQgdxZJy53N8SVbKVNemTpTmtHpkDsLcufIpCcBADEid46N9KyIljsfa2w0p5K58FS8Nu293MXMxws+27p9Z+Px49kpW4r5y4TXprU3dz50+PBt9z4klcP76XW/27l7T3ZebUtcufPAiy9dsWpNdqYtxVy2baz95p5HnvzOgEFS32P+bl7dULvZf4n4zbbthaNnyZ3Nqpm38PNc/xfmXWr6b4Y6duzYMy+9IW8UHrmziJw7m21yS9vsz2whK9esL5Be1Vx8+V9ffG3Xnr3ZCVrKvroDt4x+TCojLuTO7ULu7AC5s0hV7txz8Ahz9uU/ozCHBnOACHpws5nqob/9wxx0ZEJzwvb69A+kcudC7izInUuN3FmQO0cmPQkAiBG5syNjnn3Zjh2DLozNH81L2UpNTWYSM6HUKeCn/znqy9Xr5Ermm23bg54jYV/MS/lw3gKpHN6LU6YfP57n3h9T/LlzBHmv9I7UNz/lIOS9Qk8894rdz15ZuWb9kMuulpo5HVw1Rt61E0uHuCHbcOHcuXN567059noxF//TZ88Lsy2ZPWvF17pOF3y+XKohLi+9OcPsp54ly7+64rd3SQVP0ZgyOST2NcVxECANOCkjUsdz55AbBhCv16d/IJ/3H2tsnDF7XpifCjSHmHc+mGvqZ6fMlPqGhkf/PlFqAkWFHAPN8SW7qWVKGeTOQFwkIgEAxIjc2RE3ubNhrmTmL1qanT5Tjh079vQLk6WaR3LnhobWu1kLpNWFmQZ8uWptdi6ZRbCvymIJNZ6aMMnuTFP21x2885G/SbXCbhn9mNysevz4iTfenS3Vcjq+aowhl11tLgmys8gUc805buIUqZZM5Zo7m+1cfgNz0dIVIT/AMMw6XV+7JTtlpuyrO3DDHQ9INbhE7hxeeeTOgHv+pzPVNzQ8/Y/XpFphE16bJk9tqt2yLdrZF1AUuTMQRCISAECMyJ0dcZY7Gzfc8cC+ugPZWWRKUEQoufNXazfk7lMukFYX9scHxx483LoIS5Z/ZS9Rx0ONn910x7c728Q05sLPXP5JtTD8F43mf0fe97hU88Syagwzf3nTxV+slDrJVK65831Pjj9S33rZf+jwkTseelrqFHb/2Oft4MDsRPzA4MlF7hweuTMQwaAf/nLF1+uyG2WmRAidPbPmfipfuOEIghIhdwaCSEQCAIgRubMjLnNnY3nbZx+bi3ap4JHcefqHH9u3AEd7XID9yIIj9Q3PT37bXqKOhxr+K7SOPA/Rf+t00L2uca0aQ9bOhs1bzBWs1Emgcs2d5TJs6/adP/j1rVKnMLP61m7cnJ0+U8rpISSdEblzeOTOQARPvzD52LHWA6I5Lfno0yVSJyT/ILB63cbw37kBwiN3BoJIRAIAiBG5syOOc+f3536SnUWmBEVpkjubE9AFny/P/k+kxwVcfOWNm7d+m52+qWntxs0j73vcXqIOhhq/+v1oeTjGV2s3dCS0NZd2i5auyM4rUw4ePvzHB8dKNSOuVWO8/f5H2blkykkJeiIo19z5o0+XZBcpU8xOIRXCkHUabSaISyeKKf2RE7mzf311ohWKNPB/1rjl2x0d2XHkNwYOHDz0u3selTpAx5E7A0EkIgEAxIjc2RHHubOcWQbdUWtfzJtiprLbefz4iRenTJdJCrMfOGAuosyllCxRB0ONV99+z742O1Lf8Jexz0ud9pIHg5iS9zcV41o1hqydMH1y6TUjzVRmfdUdOGj/DJH5t/nL2g21U2Z8aOrIVGEMuexqM2ezhRw6fCTXt6Zjv9m2XeYZIXf+1e9HT5s118zc9LD9mO+GhqP76g6sXLP+hdemFfgtxzBqLr78ry++tnbjZu9ZGRE2MLMgXqu8YjpZKoTxxHOv2J0Tfiamh00/my46fKTe7v+t23earou2To2eg0fc/sBTH326ZOfuvfZz282czV/M382rybyfruMr1OhEMaVZOrOM2bZmitkfpU5hZi8zK3T33v25kcH8w/zv4i9WhnnqvTSgvR0+8r7HZTMzm7Hpc7MKzHoM8+tqRtH1VYoVatr21IRJK75ed+DgodzoZJbCLEtHdr2cEu3aOabnzSreX3dQGm9WR4T+Kd2IEcsWkjTydKYIJ0vid/c8arbD7Oza87AmcwA1h1HTmfZmbHrYHNDNthf5xMDmnSSYU4LcIps3Mhue2fzMypXKnryDkjnoL1n+1T1jnol86PFv86ZJpmGmeXlPJHJHk9w+aP5r/u0/vUmIeHfqvExfeXP2SnsPN0AZk4gEABAjcmdHHOfOcvflV2s3SAWPfTFvijkBld9YM+fr7bqb2H+7tCxRtBTJ47/D6MtVa2PJzsyJfnaOmZK3kXGtGkPO+wv3yU//c9TyVWtyFyEFiqnzxcqvw19KmXX98YLP7M3SX8w8zbubNpj67cqdb713zPraLbm0pUAx8zTXVAXSZ8nF7Pe976nn5P73CBuYfDnAzPCqm/8kdUrB6//cZXneYvd/eI+Pf1m6JW/ZvXf/319+o8AeFPkC1R5Y/GukIyvU/pDAHkWlqYVL7h3lUfjtfaj9HQ89fejwkezEUX+LVXrDlLz9bHep+bf3R7Ozm82jwF5mXtq4eav/WGN3Y9EStN7NPm5mXngfP3ykfur7/1U0W7SXLu/BsWiFoA0jL9Me0yrTtuwE+Up9Q8Mb78729o68nV9AXLt20J5ilq5wz5uXzMzDHwviGjFEjFtI0shRwz/KtZc5vdmwuc3v05rDotQRZuP5ZMmywkdwU0IeROzju/mHd3pj1rXZC+RnD+1iVq5pg334DjMofbtz1+0PPJWbROTd3Ypu82Ykv+/J8bmZGM++8mbdgTa/pSHFLOaH8xYEbXuOD38d36mDxkDzD/O/2ReKlVyD5VrAvPtb783xZhiGOYmyhxTvckDqAEkjEQkAIEbkzo5IZhd0YSwniLmz//aSINVcI0kFj31+bIp3Ym1fUAU9dCKvn910x87drSeaXigsS9SRy7PINwQVJQ9qPFLfIBcwRlyrxpBPBdZuqA26kjcNs2+qClPMuf4tox+T+fiZq74wQYNXzII/+sxE2YZz10vCLMuUGR8Wzlz8ZX3tFrP9yKw8Qddpr70zy/8uETYwsxWZbSk7feb6atqsuVIndmYDsxPPwsVcPJv+lznkZa7/lyz/qsC1qxRTc+mK1UFpqeML7zArNOjSWppauNibrgyV7Xqovb0jt/eyPEd6w5S8/ezPYsxuHnIX3u/75VW7G4sWf3vMPv7OB3ND7uOmZ9Zu3By0d3vspbNXa/gKQRuG3y9uuVsCvqBiWj5/0dKaiy/3d34BMe7aefcUU98sYPZPBcvW7TsLd7sR74iRE/sWkij+jDjvd6RK6onnXikcqkoxJxLPTZoqM7HZx3fv9MZsG59/uarotmEqLFz6pXcO05FBKce/u4Xc5s354T1jnjH1TWPMGmkM8Wm9afzHCz7zGi9cHv5i2amDxkDzj5AzN8VusJ6ptuc2lHETp9i7f7RfiwEck4gEABAjcmdHJLOzTwptcoIYLdw0Z6V2/lvf0HB/wMMo7PNjU7wTa3nuRFBm7Wfnd+aM05x3mj/KEvnPwsOTfHDv/rpr/nCf1IlGbs0w5bV3ZmVfrR7mufGuB32r5qXcq+2y/Ks2vys4f/HSthWGe2/95POvFrjPqECp3bLtkqtubDvPNv7wlyf2h05GvGJa8v5Hn9jbsHe95Pf69A/CXO/5yxcrV/cc9H1pqnHZtSP1Oq162GvvvJ831IiwgcnnGaaYhY3rI428nv7Ha+1ds6b+k8+9YneLn1npX63ZkJ2gPWXlmvV57zd3eeGdN3Q2RSYPurSWphYu9qYrnzmZcSDk3e6SPbXrIzqb9IYpeftZshgzyG/dvjP7/yGKpBV2NxYt0p6aiy+fv2hp0TRKSuEM1F66fAfH4b4KD8rG79swtILnltGPhv+8zRSzmNNmzZXOb9u21mOE8fQ/Jse4a/uHvvYO3V+t3Tjsylv/+fyf5PWD39y5al1ttmp7ylfrNhWYbc3FP4t9CzkJfKsj54ZR99uZrzksPvHcy1Inkuyhv6ig0bJwMcfl6bPn5c1YDcmdzcC44ut1IVeimbM5Yv7h/ifNWVn2TyFK0BOxZXd7fPzL4T99Nyc/P/j1rR99uiT85mca/+rb70kbDGeHP9Nv++va8RFC0PHaNwZ2NHeWa4FDh4/c8dBY30ab3+IvWn83JfNFoklSIRRr6YqQCR2oCbu3yvDowHfO+w9pQ+c0XPu89CQiAQDEiNzZEZe5s7lOts+5C/zynn1+bIp3Ym0q24+zCPnlcXMx8+Wqtdlpmpp27t7rXUPKEvnPwsMz1xLZuWTKhoCHVkdjeik730xZ/MVK88fKARfldpXrRt5lp5MNR48+/PSzuVfD+/09Dxw81Dofc/U49rmJdoXu/QaZt/b/gqK5OjLr6+l/vHb1yHu9S8f/fe3v7n1s7BcrvpJL0OPmIvDVKfY8bVfccOvO3XuyVVuKWbR3Z3908133Dbz40u8MGHTVjSOffPYfq9aub2xsTZAbGhrMnLP/0za8y7nzkb/ZTx4wxXTU58tXmnb+5JqbzLvnZr563Qa5MqyvbzDV7KZ6Rlx57dZvd2QrNTXN/WThLX/6y766/Ne3ETYw05lfrPw6O31LMW3buHnrfU89F3SVHpn/44TDR+rnL/7iT4+O8y4m//d1N5vVt3mLfuXWLLJZcOmcnLO+94MvV+lSeJ3/2LjnvM43K3fUXx79+NPFh4+0WUfmjfLe85WEC2+ZPOjSWppauNibrnyb2OxK3gdmRclDNryvd0idMKQ3TMnbz3aXmvF5xdfrvH+bdWcmnzLjQ9MVNRdfbtrwmz/e/9Z7c+ReSFPNvovf7saixW6Pmb/ZVOwt0/zbjFSmAeZ9zaumDbfeO+b9uZ/4b8YMiksMe+n8B8ce/YeYsSj7cmawMqOxvfEbZljIvhxQwTAjyTfbWn/21iv+oc/sfaZabhnNWt61Z5/3b1NMU+22Gaf0qvHmb3Y0M4hl62WK2dHM7mZ2OjNzU8Hshu3atWXoW/jZF7n2mzmsr93y4pTp3uHA6/YP5y2QseXY8RPTVx//yeSjfje/e2zT3jbNMOXY8aZ1e068tfL4Qx8fM3VunXnsH583rth+oqFtyGkmW/7tiZ+/ofM0zB8/XtgmdI5lC3GterisC9ujf3vODK3ZRjc17dm3/xc33SZ1IujWd6A2I5+8H0ibvcZ0qelY072G2YNMh+/euz/7cksxZxGvT/9AZuiR3PmzL1eZyt7/7qs7YIYUb/WZFWQOVQuXfilnHeZwuXrdRu/fuTXuDUpBG6eplvc7IvZoULtlW+4DNtMes4XcP/b5i6+80VS74rd3me1fTpOOHWt+bFfujcyCmIO7mcQ7iJj/mjOoTd9ss7dPU3LnqzY3hz9zqrmlZR83rQq1Ux879sxLb9jz9AQdHM0/7JPwwsVusGmDfVZvypsz3peNNq+fXvc7+yTTjHjDf3SV1Akj5CcxFVVDZUIHKvoPkWbk9b/O/ncZIR0Y9pd50ozOqHLASVitAIDSIXd2xE3ubM5TZ8yeZ18PFPgyo2GfH5uSO7E2J765O4tDtkFuGs0lO7JE/rPw8KS18xd/IRU6Im+oHXvuPPDiS1esanOz845du3/06xvtOl7ubK7H7Esjc4nuf/RHl9PO9Ca5/c8Pm0vfbNVM+WLFV7kZ2r4zYNDny9s8WMC8y38v+izoquCmUaO3fNuaytnFDu9y7Ad8m7Jt+45rf3+nzDPnib+/cKTtI1bfnf2R1DEkfJm3YLEdsDY2Hl+7YdPE16eaFTTgX34s7Qnp9gee8ocgXjl8pH7J8q/+Mvb5WAIR+TjBdL7/S+tde5/tLfhfHv+r3D5mFvys7/0g1zO2l6ZMtT8kMGX9ptrLf3OLVPN8/4prVq9r80HLkXw/0enmwvu/l3yRS1FNaTx+fN2mb8x7maHDDGj2hEbQpbWwG1Cgmke+Tbx81RqpkJc9lRktI/+qmPSGKXn72V4iMyZ7kZBZtOcmTe2ZL+82G5V8lhb0CaI0oPAQ/cxLb9i3h5uWvPr2e3kb4D8YmTbnva/QKLy+4sqd58z71B5Uzf7y0X8v8BJhYcbJ5ydNzXuXpWmq3TbDy53l8zzzRp8tXxE0robctWXoM6Ol1/7de/be99Rz0gzPL265W26E37A3f0D8X+vtrw81l28PnHhkXqNU84yec+yb/W1qNzQ2vbosT+Xpq48fO9a60uPaQlwrmDubw022xZlS+83Wi/7jCqkTQZjc+ZbRj8lTXEynfbzgs7yHJ9PDU9//L7MKslUzxRzp8j5bWc5RvWJmPnv+Iv84bAR9a6fAGvd/vrh63UZ/TXs0yBVz3MzbbP9AlyvmLM7sDlLfMO8oH56ZNvvPct0c/swgk92p9+4Pv1Pn/Zgz5MGxXcslj8sIuamPfW6iPdX7/zVPKoRE7hwNuTMAIIHInR0pae5sTmTvfuwZcyYt2Zk5o318fKHJ5fw+dwIqP7cV5tFsdk5qrkZyT/aQJSocahTwg1/fKmferY/CiIOci3vtjDd3/vXNf1y/qTY7faY0Nh5/acpUqda936CLr7xx89bW+/LMZvDUhEnSYCOXOxtPP//SUSsP2vrtjhFXXpt7Nce02b5Ry6yyj/57wXcGDJJqNn9G6RV/7nzNH+6zw5T9dQduvft+mZt4691Z9uXfqrXrpYIh4cvG2m+8RTATmvpX3HBrrmbFgKHSpPBefmumvYf6i3k7c+m7cOmXTz7/qne/VXuZC8VFS1u/fGpmmPcu41zubMid3WYVmxWdezXHfw/7ilVr8gZqOT/69Y3yiYJ/N2/XBaqtXRfem77Z5vW86RAz4a9+P9quLEqRO8u3icM8wEcespH3drmQpDdMydvPMlabkvezKJt8yGEOB3nrSwP86ytHZmjGebMvSB0hT90xk+ddv4XXVyy58+1/fviQtZbNxlZ46KuoujDvjaWmqXbbjFN61Zj5LFiyNFsjxMyNMLu2DH1e2bZ9x29uK/QoGPnSyYGGpsf/WwPiR+c37m/7q4qb9p24dWbzPc5BHph7bPfhNtHzqp0npI7MNsYtxLWCubO9sZmS97AVQdHcWY4gppiuy/36ZRB/QJz3O3D+3DnoCOXxN8YU056g+6k99j0Npmzfufsn198udfxjXeH7J/zfsjKl8GNb5GsupvjPJ90c/rzy7c5dhQ9Ssox5D1KlyJ1NH9pP7TtypP7uh5+Q7dZv4WdfZCdoajp46NDv73lAKoRE7hwNuTMAIIHInR2Jljt3pOzYtafAL4Z75PzePgG1f27LXAoWfuappDCbt36bC+ZkiQqEGoXJybq5InrpzRlSpyNkBXmn9R3PnU8f/K+/vvmP41+abC5N5XbUoGyie79B8hX+vPcEGXbuLAlF3tzZvNeylauyNTJl3cbawumk58Y/jpa780zx585ya4y5OJf5+N1w+932hyVhcmev5O29juTORrt+qenwkXqz+5hdpsDvywu5dFxfuyXvTWp27mzIl/fXrN/ovy9yyjszTYdkazTHoHvsOD6IfAjh383bdYFqi3DhXTjjyClF7mze1P42cZibl2UP7ciPJvl7I28/y1hdNN/xfDhvQXaC4DFTGuBfXzn2E5zMP8L8/KbpW/vWQvOPot+s96+vWHLnTxa3bjmmrFqzrvDQV1F1oXnrWXPb3CJtimmq3TbjlF41EmqHHFeL7tr+oc/UN1OZIULaYJPt+ejxpte/1Nx5/qY29zrvr296dH7+O51tb6w4fsw6iJmpHm57f/Qnta2zjXcLca09ufPHny6WCtEUzZ3lEzJT5i9aWnTMNN54d7ad9tp3BuT4c2dz4lH4Wz5yxDdl0dIVhdsjv6WRd3CWsc60Ku/n7jly/mmKGZzN0VaqCfmai/98xtnhL8zHM7JTNzQcfWTci1KnFLmzYR9ETCl687I8ZCPvGUtI5M7RkDsDABKI3NkRl7mzuRIwV8thbsmU83v7BNT+ua2iQYy5hsndUCPXjbJEBUKNwuReWtOZpkulTkfkXUEFcucOlsbG4x/MnX/64H/NzT+ne79B8guK5gJJWuuxc2fDjmby5s7yaOl23bItyaYp/uu09+d+kn0tsxHKc6vzkmAlfO6c937eDubOxiU//+2H8xcebvv0j8LFdMuWb3c8N2lq3i8j2+zLwgIbsOTO32n7aBT/DUcX/ccVtd9szb6cebr3q2++Y1cIYq4G7Rvw/Zeyzi68TQn5aNdS5M6G/Lpg3m8x2+zMIm+IE56/N/L2s4zVIR+7/8Rzr9jDWt4fiZUGBA3RIav5/eaP99tDt/2pZE7h9dXx3FmikKBHydu83Flu8TbFNNVum3FKrxr73cOPq0V3bf/Qt2zlKjNV4dzZeO2dWdkJmgeopvfXtHnE86gPju042DqYmwpzN+R/BrS4+d1j3x5onVAS7T//17E91g3R8W4hrhXMnVeubvOwrDCfsIZRNHeWBDD8veFmrKjdsi07Wab4PyqTU6Aww5qc3YWZxIyraze0HnTyDs4y1hUdjQ37uGBKmElkbPSfzzg7/IVprWHv1Ob80P/TxyEPju1dLvm0o+jDmu2HbBT+rZGiyJ2jIXcGACQQubMjLnNnr5i3W7L8q5/+5yh5C5uc39snoHJyXPjM2D7fNWeo5jw195IsUfhrUSHzMUvXSXPnxsbjX329tsAXD7v3G2RfGJhWmQskaa2nvbnzS1Om2tnx+k214e9DkeDGFP91WpvNwHTgH0fLTPyi5c6HDh++/c8PSzWj47mzp+biy//64mtrN26Wm7kKl7oDB4MetmvIDlUgW5Hc2ZAbk+W3fe5++An7MdlmNZmVZVco4N3Zbe75kkvQ9l6g5rT3wjvM7WmekJfWdgMKVMuRbxPvqztwwx0PSJ2cAl/viMDfG3n7WcbqoM+ihAxr/n3WkAb415dHZpU3wg5irzWzru946GmpUHh9dTx3lueNhrkFz8udDbvxppim5hrmGXHVdfYA1a6n/RbetWXoy32YVzR3lj13zvo2sfLLXzTavxPov225gCVb2nxrx56z3A0d7xbiWsHc2d4aTXGTO5tBxgw12bds/43h8oAL/7dbZAc3hz//sziE3Lyc96EZfkUHZ7vCsWPHnn5hslTwk5uXwzyErejY6ObwZ3bqkL9kW7Q99k5U4KjX3uUym4H9S+NFP7SzH7LRwZ/cJHeOhtwZAJBA5M6O5I01pY5h/mheylaKo5i5BaWWhn1+bIqcgNo310iabJPIRhJqWaKgUKOosrnfefvOXW+9O+v7V1yTm7PwflcwDDt3lif85s2d7esBU/L+iF8BMrn/Os3Wo/8FMnle8v30kLmzd9OfVDPiyp1zai6+/L4nx3+84DOzhdsPIQ0qJ06cWL1uY94nb5j52D9T9tGnS6RCjj93ltB/5eo19qvycULQT0oW0qtG2uBp7wVqTrsuvE0JecOXEfLSumi04SePpCjw+2b2Qzbam/74+Xsjbz/bSxR+9CuarRjSgKAh2v42Q95veRdgfx/f9Jj/cR+F11fHc2f5fEXi3bxyubM8TMA0Ndcwz92PPGl/8DNn3qcyqwIK79oy9OWWq4O583+tb/OQjQ179DHN0diRdOxbiGvJy51vGf2YfdtpgVOyvCQj9q8gGSsKHKFyZOhYu6E2zDBedHC2K9QdOFjgI8Ace4M3S1HgpDen6Njo5vAX8vBkFG1PiXJnI/OhReveXWCDlwHtk8WfS4V2IXeOhtwZAJBA5M6O5I01pY5h/mheylbK3AphTiWnzPgwjIVLvzTXFXYC5ZUCD4+zz49NkRNQOykrEK/YV4z+b//JEgWFGkXJyXrsl6aygvYWe75zB8uRI/V/nzgpN3NbhNx5+I+u+mz5CnvV+3NnfajC0aOP/u05u0JRL0x6w36LvBlWTpjc+fLf3CI/tBgmd25e9b4fY/TEnjvbzBX1b+9+xOxoZq8p/CCOvL9oFP5iz587y7qTlfvxp4uzL2RKyIdstHFSc2ezQguEvCLkpbXdgALVbPJt4qCHqht2Atve9MdPesOUvP0cYYmMGHPnaA3wyOOw/c0oPPOO5872gxFCDn253Nk0xjQpO3G+3Hni61Ozr2WK+V+ZVQGFd20Z+nKvdjB3XrG9zUlCyIdsFPXN/tbZxr6FuFYwd5YhVz4tiKxw7iyff2zYvKXo/cjiq7Vtfh9YxhkZK8KM9jJ0+HeNvIqOJHaFoOFI2Bu8WQqzLFLBr+jYKDtRmA7xFG5/yPHWr2h7Qh4cIyyXOZ/ZsWt3doJ8p5c541+anEuojx479sTfX5AK7ULuHA25MwAggcidHZFz3KCTQrnEDXkCbfvpf45a8PlyuTdz7/663/zxfqlp2OfHpsgJqHy9Lu/XyXu2/bWTnbv3SuImSxT+JFv84Ne3bt2+MzuXTAlzuhyenIt77WzOnXvVeK67rU3ubK4A536ycPLUGWF8vGDx/roD2SlbSuYXop7PzT+nR7/B0ra8TPNuvfuB196esWrtevub2l5pvjC46jp7tvJl8ObnYIwabVco6oEnxzU0tL5R4WigOXf2zcH4ybW/veP+x95+78P1mzbLDy2a0pw7+yaRljc/BfWRJ6WOp6S5s7jhjgfen/tJ0O8Q+p9WbF8TdrA0x2q33ZVbajuSy2ZqVp+E0aXXmXZTcyJcoHradeF9pL7hvifH2xUKCHlpXTTa8DND2ep1G7PTBAfK8m338HdqB5HeMCVvP0dYIqNotmJIA/zry1+ng8Usi8y/8NJV9L9Ac2dr+/do7mxVuOjSK+0HoB86fPi2ex/KvRqksio7mPzk+tu372zNXPyNt9+6g0VaLkNfblTv1uccaYOQPXf22qOXTdyfs3lf68B77HjTG8vr7VejueeDQ7sP6WfekYu/k0OyN6SipdB+VD08txb8ZI3nPWxF0K3vd7UZFlmni79YKRWKsj8wM0XuaJaxIsxoL8NCyLVWeGeXCnmHIz+7c0KeNhcdG6XDw3SIp3D7pdNCLqBRtD0hD47Rlmuu9VlLc6D87Auy9Xq+WNH6y9Wbt2wb/uOfS4V2CZs7DxgqEzpgjkrSjLz+59n/JkOlA0NHz5ZmdEbNubOv20vOl5IAAOJC7uyInOMGnRSaP5qXspUi5c6el9+aab+dKR/OWyB1DLlI85+Avvr2e7lbXPP+aMwNdzywz0pU/T9WI0sU/iTbT1qbN0OJTC7J/N8Y7eCqqbn48nfnzJfPA2q3bAvz42CGacxv735k2qy5q9Zu3F93sOgzH/z9LO33bui2KxQlcwjT/2ap73z4r6Zv1236xkxr3y6dt5hVLHMw5Dot5Bdv3TDr5akJk+zvL3vFrCC58X/+4jZPKelIsYNaiUHb+/X2wqJdoBrtuvBu1woNeWltN6BANWE/AtVsq3m/4WF/CyTvjzu1l/SGKXn7OdoSFc1WDGmAf30Zkr12sPg/wiy6dEUrFNgwZAHD955HJjctkQol2rWNMKsmrwJ7bolGjFJvISHZ20nR0t4tIcf+hTdTwq+XjrC3cFPMUVUqFCVbhYwGMlaEGe2L7hp5tWtnD9m39qKFPDcrOjYW2IkKK9x+6bTwG0/R9hQYA23Rlsv+8XBT/Kf6hjwNL8ImCpxcEpEAAGJE7uyInOMGnRSaP5qXspU6kDv3HDxi/qKl2blkiv9OZEMu0vwnoBIr+0/N33pvTuFgWpYo/Em2n1x3hXyYYEjyFVT/zUQdXzX+lVJ0JuF/4M6sBftXg/z93PEVIXPwbww5Qy672mxL32zbUTQfl2bnvXCNfJ3mzCU//+3SFaslVZffZZJ9rSPF3mykc8wKMqsp96YdFO0C1SjRhbcR8tLabkD4PpFH1ef9ZS37A6q8g2p7SW+Ykrefoy2RHHfy7rNhVofs+x0s/rcounRFKxTYMGQBw/eeRyY3LZEKdts6WOSIEGbV5FVgz+1gbwQxMzGzys60wyX8kop2rYvIyy6PvDh4+PAtox+TOhHIbOVn+uT8J/xonCNbhTnnsV+VsSLM/IvuGnkV3ZftCiG3BHvRip5WeYqOjdJd4Tu8cPul08Jv6kXbE/LgGG255OuPeY99E16bljud6/gTqAD3JCIBAMSI3NkROccNOimUi7eQJ9B5yQMT836ZXS7S8p6ALl/V+mRMOdeUM9Fvtm33370rSxT+JNvPPqk1JcIdu0HkJ3dM8f8eeiyrRnJ8UwrcEvLsK29K5bzFXKnWbtn21IRJazbUZv+Ur587viJkDnkzrJ6DR7zx7uzCjz/2SkPD0dXrNj4+/mX7GizvhWvk6zSXhlx2tf2UBlMOHDz0u3sezVWQDzY6UuxtTzrHrCCzmnJv2kHRLlCNEl14GyEvre0GtKtP7Pmb8dOMovarcq9o3nu+2kt6w5S8/RxtiYpmK0aY1WEGrqBHykQo/rcounRFKxTYMGQB27U9GDK5aYlUKNGubYRZNXkV2HM72BtBSr2FhGRvJ0VL5GWXkytzCB43cYrUiUBuo5YnONtbuCnhR+Mc2SrInQuPjdJd4Tu8cPul08Jv6kXbU2AMtEVeLvvrj3m3eftiIe+ntkDCSUQCAIgRubMjco4bdFJo/mheylbqWO4s33s154v+H+KTi7S8J6BPvzD52LFsy+Vc0/7KuSlvv/9R7qUcWaLwJ9l+crEXy5fcPbJ28mb0ca2axV+szM4iU+Taz9Nz8Ijps+f5bxY2K/HwkfpN32xbuPRLs7L+cP+T9peRC1/tSC6wa8/eq27+k12hKOkB/3XakMuuXvD5crnt1xTzFzPhuk3ffLzgsxdem/a7ex7NPftYrsHMIuTmlhP5Oi0Mu9M6srsZ8kVUMzf7V/U7nhrkJZ0T1513nsgXqCW68DZCXlrbDShQzU9WonwsZI94eb/eEYH0hil5+znaEsnI5t9njTCrQ+q0q0vDKLp0RSsU2DCk8XmH9wJk5DQtkQol2rWNMKsmrwJ7rswzrhGj1FtISE9NmGT/2HJh5owo5HOuhCysKXn3rPaSB7bIl65kM+M5GzZ70UIex4uOjQV2osIKt186LeQCGkXbY28hBXbAyMslt00sX7XGftV+yIY5OX9xynT7VaBTkIgk8aauNvvbppk/tv/4xoampg0T7b/EaczcuqbVbzT/e+K67D/CMJX3fTqmdfL7F+0rYSMBJBS5syNyjht0Umj+aF7KVupYECZnt6b4zy/t82NT8p6AynfP7d/R+nDeguxfg79VJ0sU/iTbb9APf7lh85bsjDKl4z/q5Vnw+fLsHDMlzI3bkVeNfJc2b4eYi2d7azHFvPX02fMuvWak1LS162onaAss4JFxLxb+XcE33p1t35Buyu69+81GJb+wZ5NWmUWQCobUydtjkdl36JgS/hrMz/+EU3tu9vMZTOnIG9lkp+jIiOFnGpmdb6aEbLM0qeim2K4VGvLS2t4X2rWpm8bb3+GQ58zaKzHyI2iF9IYpefs52hIVzVaMMKtDbvSOMHoUVnTpilYosGGYY8Ra67sg7b07VcY9/xhVol3biLynFNhzSzRilHoLSRr5/Ljjj9yRDjRFvnQl63T+4i/sV8OQDZXfFSw8NhbYiQoo3eGvaHtCHhyjLZfHPlWWbxza30eM8cuIgEsSkSReJndualj9xk2tf0xM7tySNTf/+6ZxM8c/dG3r5L8YM37qcze1rV+UPUMAnRG5syNyjht0Umj+aF7KVkpG7mzY+fK+ugM3ZH4ETPLo1es25o2AZYnCn2TnZT9O2pQj9Q1/CX3L4ZPPv7p9527/nW4j73t8f12bLwjn/Q3GuFbNLaMfO3i4dT7+E/RLfv7b2i3bsi9nyldrN4S5Lavw1ZqEL6b99t24Ybz05gy78+U67Td/vD93t4sppub8RUtrLr7cruMnW2neC1ep08FNSJhr7+x8MyVvMBeStNMUe4eSp8Tk/XJANPbX/E23+7/WEFm0C9Si66sjKzTkpXXRaKMA+9cF7Zua7WDI9HPeXx2MoPBmkxNtiYpmK0bI1WF/QuN/AkkHFV26ohUKbxiSErbrXlGzq2YnyxT/GFW6XTvynlJ4zy3RiFHSLSRpZKWbf3fwBk/5poX/rnz5xHpD26dwhGGvIP96l7EizGgv26d/18irXTt7yG3e3uBDnpsVHRsL70RBiu6zRSsEKdqekAfHaMvlsbdS2ebtrSuWJ1AB7klEknhTVzfVLVu6pal+w8RftPwxkblzi9bJIyB3Bjo7cmdH5Bw36KTQ/NG8lK3UsdzZ/tabKeYc0f9UCvv83pSgE1D7XDMXuNjP3yhw0SVLFP4kOy/5op8pK75eF+bq6w/3P+mFy+Zy7rlJU3N/7zl4xKKlK7xZeSXkjduRV41cdfi3BPu7/Kbs2rP3V78fbVcIUvRqTb7G267wxZDsRq7T5Dp8fe2WArc550hv5L1wlTod3ISEhOl5b3UPSdppir1DyVNizEVa7qUOkrvY5NvZhT3x3CsFrr2jXaDKyONfXx1ZoSEvrYtGGwXIIJP7FMreMYNGiQgKbzY50ZaoaLZihFwddvya92jSEUWXrmiFwhuG/WRSU8Jndqaaff+7Kf4xqnS7duQ9pfCeW6IRo6RbSNLI5+6mhF87ecmXrvxfp5BPrOX3A4qSH7Hw59oyVoQZ7WX79O8aebVrZw/Zq/YGH/LcrOjYWHgnClK6w1/R9oQ8OEZbLo85OzLnSNkprW8c2kttrgvM1YE9FdBZSESSeM2589z7R8/a2VT/9dQR3h+t3Lnq7pmr92TPWuu/XTb+lkuaK9y/aF/dqnc+3VLvfY65c9HYCYs2Hcr8u7Fu2UTr1umMIU/M2+Tt3I11mz6dvcyXO9/1aV1T3aK7Wuqbvzet25S5ETtTMi+1RMa+52xcN3HuNy0XvHVb5o5vfveqWyYva2l2U33d6jdGt9zZnSmZGf54/KLWVs0eU9X81s0zt4Lp5knMezU3b93Mu2Y3L2/kyBtALMidHZFz3KCTQvNH81K2UsdyZzsXNsV/mWHY5/emBJ2AyjcHvR8Mse9uMGecctNujixR+JPsILPmfmonCI3Hj78+/QOpI8wl4tbtO7MTZCaZPX+Rdyuu/4kWQXdqxLVq5L5j/5YgPy4U8uu08i3dvP0s0XC7Mlb/ZbZcp0mo7f9hxrzkIi3vhWvk67Qw/vjgWPtiviOXTBI/yRYiF2zter629JI8E1zug2vXN77tBMp/B1y0C9SiT5LpyAoNeWldNNoozM6AcruJ3Ve56+2Ok94wJW8/R1uiotmKEXJ1yP2Y7Qor7ZHHv5kZRZeuaIXCG4bs5vZt7IVJB5riH6NKt2tH3lMK77klGjFKuoUkkJyKmH+bv0idkO585G/2scPMyv91CjnE561TgP01DlP825Js6mFGe9k+/btGXu3a2UNu8/YGH/LcrOjYWHgnClK6w1/R9oQ8OEZbrhz7S4e5rz/a+2+7TiyBRJGIJPG83Ln6lNvnbW9qWDYhEyvncufrZm5qbNq3dPJN/1FddeWYdzY1NNWvGjvMy3yb6tfNNH8fcntznab6Le88dG3VsGsfXdImQW523WwzHLeZSSbMba2QP3ee6v0jlwIH5c5jv2oOvu+68pJThl1719xdTY2rxva89vVNTfVfTb0p88eb3tmS+aM9k+qqhxbta6xbNnn0kJ6XjHho9qb6htWTsw/xyJ871zds92aYfQnAyUHu7Iic4wadFJo/mpeylToQbg764S/t79Kakvfs1j6/N6XACah9rtl8y/Crb9m3BBb4Vp0sUfiT7CC/+v1o+7YdU8z8H31molSz3TL6MZnELMvqdRv/MvZ5ecLG3v11v/nj/TK5J65VY9jd3tBw9JFxL9qv2hcPpoS8KpBgJW8/y42cjcePh78l7bV3ZtlXrabIdZq9UOE7Rz4dMTORCkbk67Qw/Pczbt2+M3wKY7P3EVP8H8bYz6sxnRkymjfkUla+yC/RVfjVKnmZ/6vx8r5hGuz/AoF/fXVkhYa8tLa3xgLVgtgJmrcx26GPWXfhd5yipDdMybvLR1siOe74sxUj5OqQrcWMnCPve1zqBLG/KuHfzIyiS1e0QuENw7+bm+Oj+aNdx2/IZVevr239wNUreceoEu3akfeUwtFSiUaMkm4hCeQ/FTGDxpPPvyrVivJvZkHnIfZmZkr47cH/Fv6hQMaKMCcesn3m3TX82rWzh1xGe4MPefpRdGxM2uGv8E5thDw4Fp1PYfZppDnhefXt98wf7dtQ3m//L14CCSERSeK15M49q++aX5eNlVty52tm72o6tOy+XOVhk5c1Nq2e7GW+W143NZv/3jar9T2jo3kmdhL9i5lmdI4xd75vSUNT/ZZZ4x68UkPhn/545IOPTp4562tzrpJtUm6GE78253CTM/c4Nxsxc0vTznnXFMidG1eNzy4vgJNJc+cuvc50rGvvc6QNQUxlab0DldXDpBl59ai6QCYUDz/9bMPR1t8mOnDw0HUj75I6hvmjeSlbqanJTGImlDo5FVUXSjM85tz3jXdnm4vJ7FwyZ4czZ8+VyY1Va9dna2TKxNebDxV53XD73fZv+m/9dkcuYjt67NgTf39B6udWqzn3NWfAXk1Twp9kF/DMS2/YYaUppm3+u7ltl14zcvW6jXYsaIoEqabHvHPovGRBQl7b5GVfVvnnY188mFLgJL5L77O9neifqs9f8Fmb243NChpx1W+8V22fLG4z823bd/746pukjt+vbxm1d9/+7DQtRa7T7IUyHfv8pLdkJn4D/+1H6zbWZqfJlNVr10sdwyyIWZxsjeBFMyoGDLWbFKRywFB7Wx3/0uTGxtadxZQVq9YMvPhSu05Rt/zpL/vqWqMcUz5bvsKu0LXvQPlsYFfwE1TshTr7X/5j5eq12Wmamg4eOjxy9IN2BSPaav3rhJfNzpudpuV7DHYz5BfVvJt8T+lVYy+XGP3oU0eO1GcnyJTm9XXltXYd87+6QttW8Ms1qfCldbfTz/Pq2yNb0GBbwPAfXbV5y9bs9E1Ncz9ZePfDT+SWa8eu3T/69Y25yiGPEZUDLspNYpPeMCXvOBxtiR575h+FsxUjfA4in6wsWroizE3f8gB9/2ZmtCuKyluhaOYiRw0z2hf+ooxZtI8XfCaHDFNMS6Sm2ZXMLml2zGyN5juI91z5nyPtfS2vort20NDXrc+50gYh0dJLr0+1Z2vEMmKsWb/RLIJd4Y3pbZ5nUngL6d5vkLeV/u7OP9uDp5ntWd/7QW4bjldFVahjhKkmE+b10pSpcuww++aDTz0j1QowBxqzLuxOM/8Oum9ajiCm5kf/veA7A7LdWMBr0949bp0QmqHMDNRSR85RZRTq1negNMaQocPbNcxmYE/oV3QosyuEOTp07X22vcEXODfr3ve7ualkec0gn3vJ88CT4xqs+/eXrVxVtKvzHv5kOA0/3oqieXHRMdBTdD6FmT3anAlkJzbnbOs22r/tYbZPs5XKJKVmTvzsUciNiv4XSDOCyIQO5N1b8zKVZRsuvRppQ5DcAQLBWnPn5kh3T1P90ueqWrLjzPMl7GG8JZbNPePC/qP3v77cOe9MYsydTxk26tFZyzbtaWh+6Edj3eq5E3/c8xLvmRj7vt2wevmid2ZtyLW2ZSbNzxXRcmjZo7Isdu4sN3EDOEk0d5aXHeh62lnShiAn4wDZ+XLnS37+2/mLltqhsyl79+3/9c1/lMmN8LmzOeE2p93Zem3L5i1bh//oKqlvrgS89phzX3MGnK3anpPsAvImAvUNDS+/NbPAVW7NxZfPnr9IeiZXzNzMPAtMLgvSkdzZvjzw3ztpPyXTlLwxjafLac17hFk10977UK5+g67Wbv/zw4esC1dTimasZuWuXN16M0uuSIZl37BmyqefLZP5CP/1tilmg5RqRviYMlrubFqyao05UWpT1m+qvfw3t9jVCrhp1Oht29tEh/4L+659BpqtS26G+irgFyPtCSe9Nd1euWZd+EMZudw1vTr300WnD/5XqWa78Y+jd1s36x0/ftz/iHa5L/JI5mc8zWWDzCrnR7++ccu3rTc8esW/vsKv0JxTa4Z7TSp8aZ3Lne0t1mzwt937UG5WIU15Z2Zu49yxa7fpT+/fpkhC0dlz5x/8+lb7MUS7gh8TITd4mrH0jXdnFxgzjSGXXb1yTWvLg+4FdpA7m1F0xddtdnPT/nfnzM/726dmr1y6YrWMTl7x586n9Koxg/CCJUuzNTLFbIH+w6IoumsH7Sm5w2sQiZb8W1QsI8aEV6dInStuuHXn7j3ZGsW2EC9WMMOvOQZlJ8jM9tU337HnGa+gT+tFyNzZrK8vV32dbXpLMadtr0+bGSYONlvIZ8tXyGa2xZdU5viPIGb7MVuRzFY8+ew/6q1fjDDFbKv+5nXe3LlLaXLnX9x02x7r4/a8Yb0t6PAna1M6zX3uLL9pId+xCMP+mtrBw4ffn/tJ7h6OoB8YL6mQe2u8KvoPkWYEkQkd6Frsg8mcROfOp5M7F2Xnzl6Y27Bo6ZYQ9zuHzZ3D3O/cts4lr5sa4XPnVpeMeHrZvqamZe/P3tTUsGx8y+3PTy+r19y5+ekc9Uufy1ZoNWrWTmtZhmWbSu4MJAe5cxEnN3c+1thozoYnT52e1+vTZ02Z8WHOmzPnmOtqO2XwijlB/OuEl+SNPOFzZ2P8S5PtW2Zy5f3/mic1jZLmzobEGV4xJ9Pmmu2hv/0j6MS35uLL5/z34mzttsXMzcxT6ttkQeLKnU2R83754aYCl+5dTjvz0l/dsPyrPPnItzt2/vAX18tK8cyZ1+aplKYUyFiv/f2dG2u/ydZrWyTDeq3tY6mbv3H87D9kbjk3jRqdd7Zfr9vgvx4OCl/8ouXOhv9uZVPMDjt/4ZIrbrhVKtu+f8U1H8ydL1f1pntNJ0vNrn2ar9vtO4O8sumbbbfeO8ZunuFNYrripSlT7XHD/DvvB1Gmph2MmmLa8NnyFUHJ161332/HQ6Zs2bbdv2Oarc6+s8mUXXv23vjH0TI3Ty58N29tR1r+9RV+hea0N3c2w2a2UqaYrrj+D38KkwTlXHPrqNyaamw8nlsLZl3f+9hYu2Znz50NO9U9fvyEGSSvHnmv1PFMeG2a/dGd+ff8RUvzfnZi+NPboPHfQe5s5H5d1i679+43R0+zY5qt3RwCRt73xMcLPjtsbcBmkh27WneWvLmz6epf3/xHO6UyxQxxZqewV0dOyF07aE/peO7c8RHjm23f5t1tm78+Em4L6d5vkD94DTMadES8ubORN200S7R9566nxv8jKMo3fzcdtb/tjySbYjY2s5VKY2z+I4g5SzTHoLxvZP74xvT37M3MFLOV5r0Lgdw595LH7CNys4XZBSIc/mTEk05znzubzrEPCuaY/vC4fxQ++xVmd849Uad5eVvOf8yxI+gHxkuK3FmQO6dG29y55yXNGWtzyQS1101dXd/20cyHlj2afb5z2Nw5zPOdT5lgxsm6uU83PyH6pqkbmoe/sLlz5lHO62Zmnrz80x+PW9acm7/Z/I6b3sk8u/nOyYuazzuyTwXJzbCqOYyuWzRx9Ihh2VbVfzWxynta9J5Fj155SdWVo19fl20quTOQHOTORZzc3LnjxUst/6l6sLyRp125s7m+2rFrd7ZqSwm6l7DUubNhTpRXfL3OvmTNlfqGhrUbat+dMz8Xypt/b9i8xX5ogF3MTFav23jpNSPlLWyyIDHmzstXrbFf9f+Cn2nelm93PPPSG1f89i5Toebiy83F54TXpq1eu96+Xc6+2jEb218nvDTgou9fc+souYdO7i/zirl2/WLFV/c+Nvai/7jC1DFXeubf5i/28w137d5z1NqGJcOSrwCbkunVDQ88Oc67bjTve8Ptd5ttbPOWrbm1Zv5hN9tch9/98BOmpr13mMnzhi9+kXNn45G/jrdbkiumheZC/bPlK16fNrP1I59pM5d8sdxcheYWJFfMX5Ys+9Isgszfy50NSe5MMf9rrtif/sdrufVrFv+1t2fI/M2/C3yrOm/8cfjIkY8/XTzqL4967fnJNTc9+ew/zF5vbzam1Nc3jPn7P7zmCXkAtymmsmmGucw+ffC/msZcdePI8S9NtudpLr8XL239XT7/+gq/QnPamzu/OeP9bKV8xR8x5GW2/+wEVqn9Zqu3j+SUQe4sX1aQYgccPQeP+GKl3uB5+Ej9/MVf3P3YMxdfeaOpY/5r/m3+Yqe3phR4+q2b3Nl49JmJ9jBetJh98/XpH9jv7oVrttyTZ/xP7DH/a1ac2enMrmcqmF2mXbt20J7S8dzZ6OCI8dg4/91GzcxShNxC5i38zLxdtkamFJhtXGLPnY3Lf3OLvye9Ypbo63Ubps+akzt2mH+bv5i/Z2tYJeTjoZ987hX/5ObQ+e7sj26+6z6z4nKbmX1/ulcK9DC5c+6lnCf+/oL9YBlTTAe29/CXtNxZfgBZSsj22L8vmit7g39gvKTInQW5c2pI7lx9yrDmYDeXHVfdPXP1nuzBYt83i8bekrmJuF25c/OP+M1e7X3o3Niwb/m8Zb7nbJzS86bxy7OfhtZ/s+gd8+9M7tz8O4GmZDLfwPudr5u86NuWT1Lr61ZPfbCq5TkbzaVuy9xX5jX/8uHXMsNLrnll2XYvLDGtWjf7Lu/xzddNXtbS1E2fzvaaSu4MJAe5cxGdOnc259+vvv1ez8EjugQ8ktU+vzelcO5syEMhTQl6FKOD3Nko/OiM9pZde/be/sBT8hY5siAdyZ3l+sH/xXaz1tq7UJu3bJ0684Ps/1gl72Vb3sShcNlXV2eumQvkzsZHny6xw5SixVT+ctXX8xcuyf6/VcyWmWttUPji15Hc2bj74SfkVrL2lgK3nuVyZ7M/Tp89L8JGW/SJKDf+cbTckximmAvmSW9ND3ogYN4vFhQoXq5h327sX1/hV2hOe3Pn39/zwMFDgQNpyNzZHzqYLXbKOzOlWhnkzv5PF+wiAcel14xcs6E2+1ro4gW49nxsznJn474nx9s/r1qgmDabXdXssCFz5+/ke+RRmBK0awftKbHkzkZHRgyZle3Sa34fZQsJ8ciIjitF7mx8/4prVq3J/yl4yLK/7sDDf5sgzcivevj4lybnTa4LF3N4KvAME3Ln3Es5Zq/0f0hfoOQ9/MkZr3Sa+9x5kO9HVu0Ssj3++wxMKfAD4yVF7izInQEACUTuXEQnzZ3N9c/62i257+93iSl3vvexsfbVjnmXl6bkn8RN7uy576nn7KeOhi+Hj9RL/HekvuG5SVNl/h5ZkI7kzvIkDf+XE3sG/KRV3mKqed+Plm3MK0GXbT/69Y1r1usPLQYVs00++NQzZv6Fc+d2ZZSNjce9iNZsQv5mnJTc2fj+Fdd8seKrkN0iZefuPfc88qTMMCeXOxtm/b769nv2NlC45FaxzNPv8t/csn5TOxIfszu/MOkNM2FQ7mz87KY77Of/FihmbuNfmmzmdtJz5+8MGOR/nkyuhMydTYfbvy5oSt2BgzfcfrdUK4PcucB3R0zxBxwFHn+ct5g2eJ+AynxyXObOhmm/GWDtL3P4izmmmCOLVz9k7myYDU8eoFG4FN61g/aUuHJnI/KIUYDZW9u7hZgeM/1mek9mFbsS5c6GOZa9Mf09+wQpZDG9ZA46l/7qhh5nnC/NyK96uHm79n5KagaNR/9W6F5ycufcS7bwH9IHHf7kjFc6zX3ubDw+/uXcwzGkhGyPGczlGVwFur3UyJ0FuTMAIIHInYvoXLlzQ8PRnbv3fvTpkpH3PW43r0tMubMEMc3fqrt1lNTxuMydjZqLL39u0tRde/aGudA1dUxNU9+bSs6/G48fnz1/kXlJ3kIWpCMn2aYHtrRNmr7duetnN91h1zGn9S+/NbPe+jn1vGX3nr1/nfCSd7lu1s6mzVuyL7SUApdt5jr5tbdnFN7eTF+t21h77e/vNPWL5s6Gdwd64UDHzPObbd/mIlr/c1FNOVm5s+f39zywcvWawkuRK2ZxzE4xZtzzhUMTO3f23HrvmPW1W4pusWYv+/vESeETmTCr1RTzvqvWrMs9f7ZA7mxces3I5avWFGiqeWnb9h233n2/N7eTnjsbpsf+8vhfzYZ08NAhaXnI3NmQ53UsW7nKvyLKIHc2vMFww+Yt/jzCH3AYZoAy9YveOGx63v4ENIjj3NljtuopMz40i3z4SL23hZj/Hjx8eMXX656aMCl3CBj0w1+aOt6cTSmcO3vMbmWGTdnq/KXorh20p8SYOxvRRowCvL01/BZi+irMbGNRutzZ4z3xX54fElTMsm+o3XzXg9nvOLcrdzbMEf+j/15Q9EMOcyBb8sXyS391gzdVEHLn3Eui6KfR5qUChz8545VOC39KLDu1f1hu1xj4q9+P/mTJMnPqJfdehG/PuIlT7HOkb7Ztz/sYdwfInQW5MwAggcidi4grdy6FkFdQRpeA3Ll0il4Yl8jPbrpjyowP126orTtw0D4nNv82fzF/nzZr7g13PGBPcvsDT8nt0uZS+ZbRj9l1TpYhl139wmvT1m7cfOjwkdxlT0PD0d179y/+YuWdD46RzMJcW36+fKW34I2Nx7/dsXPCpCmFI8vTB//rmHHPL/3yq311dblviDc0NOzYtXvOvE9/d+ef7cpmH5QW5nXpNSNfnz5r85at5vI71+wjR+rzztO4adTotRs2ee9uGr9p85ZH/jpe6oQRV+7sGXjxpaYZny753DT70OHD9mWnWZbde/Z+tnzF+Jcmy9N+g/hzZ4+5/Ht3zvyt23fmwi9TTCeY+S/87Is7H3is8OoL4q1W00Izn9yOYOZv1siWb7dPnzVHfi+xcO7sMU2dPX+R6Q2zeeRmuL/ugNl47nnkyWjtDCmXOxdm586xGPvcxFzvHT9+3LudTXQwdy6pHmeEvTaOpufgEfeMecaMRWZEsp+ef6S+wWzSZsM224xM0un85Prbt+9s/WGDMLmzx+xiZkczu5s9DHZ81zbCH17NsCPTBmnviFGAvbcW2kK+3dGu2cai1Lmzx6zZW+++/93ZH22s/Sb8saO9ubPHHKeee/m1VWvXmzOc3BHcvOOBg4fMHye8OiXkEaqwMAcIj/sT9S6hdwc7d24vs6F+MHd+hMOftKFsyHOi35/7iVRwhtxZkDsDABIoAblz6FPGLr3OkmkdCJkpmIsZc/x2zJxsSTOCdDntLJm21MKf9yTBpdeMXL0u+9CJkL/tkwRmtcrmWmpdTguVOxs9+p+MT2LC5s4nIQEMyp3zkmkd6Nb3u9KGIO4/xDJC5s7mQkUGog6yn2i/Y9fuH199k1QwwufOMqEDPUJfGyOIxCv+e8aDcufS6dr7HGlDkG59w+bOMQq5t/bol//njkvKTe4cTbTc2Y125M7uzzZ7hz3b7H76eTKtA9KGsvHWe3NyH6gcPHz4jw+OlQrOmBM/2VwdqOh/gTQjiEzoQHnkzj36xXw6F4avtQCA2GjuDKTTkMuu/mTJsmONjQV+/ApAetxwxwP2UwIKPKQCZezFKdOPH2+9X/W1d2ZJBQBIlUt+/ttvtrU+9nr1uo09gx/fD3QWEpEAAGJE7gxkmfPmkfc9PuiHv5S/A0ghO3Csb2i4f+zzUgGdxcVX3rh567feqjRl+87dP7n+dqmTlzko2D+f1dBw9JFxL0odAEgVczTM/fqI/5exgU5KIhIAQIzInQEAaGPQD3+5duNm77ralA2bt/CJVKe2fNWa7Lpsz6cIfxn7vP1Di+F/dAsAytWCz5dnx8Smpl179l5185+kAtAZSUQCAIgRuTMAAG386dFxh4/Ue9fVJ06ceOu9OVIBncurb7+XexqpKSvXrB9y2dVSR5gK62u3ZCfIlA/nLZA6AJAqV4+8d9eefdkxsalpwefLpQLQSUlEAgCIEbkzAACthlx29co167NX1U1NO3fv/dlNd0gddC6/+eP9e/fXZddo5rOEBZ8vLxA9X/Lz3674ep0dVe+vOzjyvselGgCkR8/BIz5e8FlCflEQiJdEJACAGJE7AwBS7YXXpk2Z8eHVI++tufjye8Y8s3Hz1tx1tfnHtFlzpT46ozfenW3/QqApu/bs/euLr5mVblcz//vcpKm79+7PVsqUxuPH+clZAGnz6DMT350z/7d3P2IGRvPf5avW2J/GLVq6gl8URNmQiAQAECNyZwBAqs1b+Hn2MtpXvt25i5udy8OQy66WW5i90nj8+MHDhzd9s23dpm8OHDxk/jf7Qksxk3y84DPiFQBp88rUmdlx0FfqDhy8/YGnpD7QeUlEAgCIEbkzACDVgnLn+oaGJ59/VSqj8xpy2dWfLFnmj54LlMbjx2fPXyT3RANAGgTlznwFBOVHIhIAQIzInQEAqZY3dz569NjLb82UmigD9z313I5de4qmz6bClm93mMoyOQCkRN7cufH48Q/nLeArICgzEpEAAGLUJneurB5+Ss8ax7qf/l27DZ1Uj6oLZLkcqKi6UJoRpEuvM2XaUuva+xxpQ5BufQfKtA6cWj1cmgEkhNmvZXN1IPxgkmTdTj9PliukF197a8/efY2NzQ9YOHHiRN2Bgws/++K6kXdJtbwqq4dJMzojWSgHuvYJe4wokZH3Pf7Rp0u2bt95+Eh9LoM2/zh0+Mimb7a9O2f+r34/WiZBSnTvN0g2VwfKYyRJ8tlmklUOuEiWy4EeZ5wvzfB79JmJO3fvPdbY6I2QZrRc8fW60Y//XaoBZUAiEgBAjCR3HiYvO9CtfHJnXbRSa0/ubE4xdfKS6tr7bGlDkG59Bsq0DpA7I7EyubNusaVWUXWBNKMzyuTOumilVi65sy5XqZVHWoSy1P30QbK5OlBGubMuWkl1CX22mWSZ3FkXrdR6nDFYmgGkmewgAIAYkTvHg9xZkDsD0ZA7R0buHJkslAPkzkgscufIyJ2jIXcGTjrZQQAAMSJ3jge5syB3BqIhd46M3DkyWSgHyJ2RWOTOkZE7R0PuDJx0soMAAGJE7hwPcmdB7gxEQ+4cGblzZLJQDpA7I7HInSMjd46G3Bk46WQHAQDEiNw5HuTOgtwZiIbcOTJy58hkoRwgd0ZikTtHRu4cDbkzcNLJDpIQ/9e/XAkA7SLDSEKQO8eD3FmQOwPRkDtHRu4cmSyUA+TOSCxy58jInaMhdwZOOtlBEkLiJAAoSoaRhCB3jge5syB3BqIhd46M3DkyWSgHyJ2RWOTOkZE7R0PuDJx0soMkhMRJAFCUDCMJQe4cD3JnQe4MREPuHBm5c2SyUA6QOyOxyJ0jI3eOhtwZOOlkB0kIiZMAoCgZRhKiTe7czJz4OlZTLgmgLJcD0oACZEI3pA1BqofrhA5IG4BEkc3VgfIYhxlMIpOFcoEP/5BUjCSRyUK5wEVEVGVz/QXEQSKShJA4CQCKkmEkIXy5M0rjlakzm2ItZobyFpHNW/h5dqZNTUePHhvz7MsFKhw4dPjGux6SChGYdzHvlZ1prIsDAAAAAEAYEpEkhMRJAFCUDCMJQe7sCLmzIHcGAAAAAJxcEpEkhMRJAFCUDCMJQe7sCLmzIHcGAAAAAJxcEpEkhMRJAFCUDCMJQe7sSBpyZ1nGwi0kdwYAAAAAnFwSkSSExEkAUJQMIwlB7uyIZLL76g5MmzV3yowPI/vdPY/KW0RG7gwAAAAASCGJSBJC4iQAKEqGkYQgd3ZEMtltO3Zddt1tUudkKZo7v/TmjJVr1nuWLP/qit/eJRU87cqdb3/gqWVfrcnN9tFnJkoFAAAAAABKSiKShJA4CQCKkmEkIcidHenUuXNI7cqdAQAAAAA4uSQiSQiJkwCgKBlGEoLc2ZEE5M7Dg/hy55ekQkhlmjvrYpaeNKAAmdABaUBhMm2pybsDSSNbrAPSgM5LlssBaUABMqED0oDCZNpSk3cHEkU211KTd+/UZNEckAYUIBM6IA0oQCZ0QBqAsCQiSQiJkwCgKBlGEoLc2ZGTmzt36VUjK94295OF2WY1NTUcPfrw089KhZAmvj41O5dMKYPcuaL/hbKMDlRUXSjNyK96uEzoQNc+A7UZAbr2PlemdUDaACRH5YCLZHN1oMcZQ6QZnVG3vgNluUqvRtoQpHLAUN+0Jde93/nSjCBdep0l05aaOdmQNgAJ0b3vd2VzdUDa0El1Oc31SHJKrzOlDUF6nDFYpy29igEXSTPyOxkn6t37DdJmIBzpyYSQOAkAipJhJCHInR0hd+6MyJ0FuTMQDblzZOTOgtwZiIDcOTJyZ0HuXJakJxNC4iQAKEqGkYQgd3bEfe78q9+Pnj1/0c7de4/UN3hveuLEiQMHD3256usx454/ffC/5jaCTpQ711x8+VMTJi37as2+ugPHGhu9NzLLdfhI/dbtO9+dM98stUzSXkMuu9q0/Jtt26XfVq1dP/6lyXa/lQi5c2TSBiA5yJ0jI3cW5M5ABOTOkZE7C3LnsiQ9mRASJwFAUTKMJAS5syMuc+db7x2zvnbLiRMnsm+Wrxw+cuSN6e95KWrR3NmucODgoetG3uX93fzD/G/2hWJFFnnMsy8fPXos+1qIkPqSn/92xux5h4/UZycIKGapzbKbHpDJhb06Dhw6fONdD5k/9hw84o13Z9c3ZOPmvGV/3YG/vfByrmdKgdw5MmkDkBzkzpGROwtyZyACcufIyJ0FuXNZkp5MCImTAKAoGUYSgtzZETe5c8/BI159+z07zy1c1m2s/dGvb0x+7nz7A0/t2LUnWzVEOdbY+M4Hc01vyHxy/LnzkMuu/vzLVYXDeq80Nh6f9Nb0XOfEjtw5MmkDkBzkzpGROwtyZyACcufIyJ0FuXNZkp5MCImTAKAoGUYSgtzZETe58+vTP2g8fjz7HuHKN9u+XfjZF9n/SWTu/Pj4l3OPvAhfTpw4seDz5UMuu1rm5pHc+Xf3PPrxgs/ChM5eqa9veGzcc7n+iRe5c2TSBiA5yJ0jI3cW5M5ABOTOkZE7C3LnsiQ9mRASJwFAUTKMJAS5syMOcudnXnrj2LE2dzqfOHFiy7c7Xpwy/ec3jvzOgEEDL770htvvfu3tGTt378llrOYfR6yHVyQtd/7D/U/urzuYrdRS6hsa5i/+4k+Pjhty2dU9B4+4euS9ZhnNkkpwbP734wWf5b3rWXLnDz5ekMvrzf+aqe5+7JmLr7yxov+FI6689sln/7Gx9huZ+bqNtaY/c10UI3LnyKQNQHKQO0dG7izInYEIyJ0jI3cW5M5lSXoyISROAoCiZBhJCHJnR0qdO//mj/fv3V+XnXumHKlvmPDaNC91NZeC9lr/zoBB41+abMfNudKu3Fm063cFw+TOpou2fLsjWyNTTpw48eWqtZdeM1JqGmZJn5s09cChw9mqmWLe4qkJk6SmYa+OxuPHvZaYf8xftPSSn/82V62i/4Xeopkee23au42NrfeS19c33PvY2Nyyx4jcOTJpA5Ac5M6RkTsLcmcgAnLnyMidBblzWZKeTAiJkwCgKBlGEoLc2RE76DQl9tx53sLPs7POlPqGhieffzX3qrkUlBVv3P3wE/vrDmQnaCmJyp2nzZpr32Vs/j1/0dKaiy+XarY7H/mb3B+dt6tldZjSePz49Nnz5OboXO5sfGfAoAVLlmZrZ8q7sz/KvRojcufIpA1AcpA7R0buLMidgQjInSMjdxbkzmVJejIhJE4CgKJkGEkIcmdH/EFn5OIPUm+444F9VoJ84sSJabPm2hUqq4fl9erUmfI86KNHj4159iWp9rEVamd+he9BqeCRZcwbJecUzZ1/dtMdO3fvzb6cKavXbQx6XrPtqQmT7DkfP37ixSnTpY5/daxcsz7fzIfbC3j/2OfqG1qfNP3Vmg32q3HxtSGQTOjEcGlDEN+ELkgbgESRzdUBc9ErbeiUqtuMw25oG4LJhA6EX60yoRvSBiApkj2SJJkslBvShkAcINoqk+P+ySARSUJInAQARckwkhDkzo6UNHd+67059n3B4W+mHvTDX67duDk7WaZkcueXpZp9M3Umd35IKnjizZ1fnDL9+PHWhTp0+Midj/xN6uTVc/CIL1Z+nZ0sU8wymiW160hT6xsa7h/7vF0hr59cf/v2nbuz0zQ1bd767cVX3ih1AAAAAACdhUQkCSFxEgAUJcNIQpA7O1K63Lnn4BGr123MvpYpb7//Ue7VosZNnHKssTE7ZZJy5+Wr1mRfy5QFny+XCgXcP/Z5+8bkQ4eP3PHQ03YFaeqGzVskmM7LdLvp/Ow07cn3AQAAAAAJJBFJQkicBABFyTCSEOTOjpQud77q5j/t2tP6PIoj9Q33PTk+92pRMnlCcme5s/jYsWNPvzDZrlDYoB/+csPmLdmJMw8eeenNGXYFaapZQPvVIOTOAAAAAFBOJCJJCImTAKAoGUYSgtzZEQk699UdmDZr7pQZH0Yw/tW37Jtz73jo6UOHj2Tn29S0fefun1x/e+7VML5auyE7cWJyZ1moXXv2XnXzn+wKRX306ZLsxJkiyXK7mppD7gwAAAAA5UQikoSQOAkAipJhJCHInR2RoDPGyFIC3LUbansOHiF1CrMj2oTkzvJqyOdg2Ca8Ns1+PPRXazfYr7arqTnkzgAAAABQTiQiSQiJkwCgKBlGEoLc2REJOmOMLGXOy1etkQpF2XNISO7c8YWS+X+9fpP9aruamkPuDAAAAADlRCKShJA4CQCKkmEkIcidHZGgs3S5c8hHFdvsOSQzd46wUDL/rdt3/uDXt+ZebVdTc8idAQAAAKCcSESSEBInAUBRMowkBLmzIxJ0kjuTOwMAAAAATi6JSBJC4iQAKEqGkYQgd45HRdWFXXqfXcBLU97OppWZsnX7jhG/uF7qtFdF1VDz1i+9OePEidYHGS/+YqXdME/X3ufItDa7bUePHn3kb89JhbmfLsq+3NR04OCh3/zhbqngkWWMMXfmORsAiureb7AMSg5UVg+XZuRVOeAimdCBHv0vkGYAQOl07VPobLMUuvYdKG0I0r3fIJnWAWkDgMSSiCQhJE4CgKJkGEkIcud49Ki6QHpWTHx9ajatzJSt3+4YceW1Uqe9KqouNG9dOGD1dOlVI9Pa5sz7NDtxU1PD0aMPP/2sVJj7ycLsy5nc+bqRd0kFjyxj4TC3cO4sr0b4sUR+VxBIm26nnyeDkgOV1cOkGXlVDrhIJnSgxxlDpBkAUDpdep0po1Cphc92u/f9rkzrgLQBQGLJzpsQEicBQFEyjCQEuXM8TmLufMvoxw4ePpydb1PT9p27f3L97XbbjMK588rVa7ITJyZ3vuOhpw8dPpJ9ralp1569V938J7tCUe/P/SQ7caZ89OkS+1VyZ6D8kDsLcmcALpE7C2kDgMSSnTchJE4CgKJkGEkIcud4nMTc+SfX37595+7sfJuajtQ33PfkeLttRoHc+afX/W7n7j3ZiROTO8tCmZqmvl2hsEE//OWGzVuyEzc1HT9+YsJr0+wK5M5A+SF3FuTOAFwidxbSBgCJJTtvQkicBABFyTCSEOTO8TiJubOxfFXrDcumfDhvQa5hngK58xN/f+Hosdb8NyG5syELteDz5VKhgPvHPl/f0JCdMtPm393zqF2B3BkoP+TOgtwZgEvkzkLaACCxZOdNCImTAKAoGUYSgtw5Hic3d35xynT7WcZ799f95o/359pmBOXOZ33vB/ZDNkxJTu4sC7W/7uDI+x6XOnn1HDxi0dIV2ckyZfW6jfJ4aHJnoPyQOwtyZwAukTsLaQOAxJKdNyEkTgKAomQYSQhy53ic3Nz5ZzfdsXP33uysM2X+oqV20hqUO49/aXJj4/HsNJmSnNzZv1Ar16wfctnVUs3vqQmT7Dk3Hj8uD9kwyJ2B8kPuLMidAbhE7iykDQASS3behJA4CQCKkmEkIcid43Fyc2dj2qy5J0603h3cePz469M/yL2aN3e+/c8P76ury07QUjqSO78w6Q27DW+//1GuAX5Fc2dDFsr8++MFn8mdy+LOR/62v+5gdoJMWV+7xZ9WkzsD5YfcWZA7A3CJ3FlIGwAkluy8CSFxEgAUJcNIQpA7x6O9ufPe/XVvvTtr8tTpkd398BN27nzZdbdt+XZHdu6Z0nj8+Oz5i2ouvty86s+d//bCywcOHspWtUpHcmczoZk8W6+padeevQ+P+0fQHcphcudLfv7b2i3bsjUy5cSJE599ucr8XWoaPQePeG7S1AOHDmerZsqR+oa/jH1eahrkzkD5IXcW5M4AXCJ3FtIGAIklO29CSJwEAEXJMJIQ5M6xqaweXoAEnR0vHy/8XBrwh/uflFt9TTlw6PD7cz+5ZfRj1f/60//foP/n1yPv/ceUd7Z8uyN3H3Hj8eM7du3x/m3K0aPHxjz7kjTevFf25cwMb7zrIangGfXQ04cOH8nW8xVJacPkzkbehTp8pH7+4i/ufuyZi6+8sefgEVePvPfFKdPthfKK3PRtI3cGypIMSg5IAwqQCR2QBgBASckQ5Ia0IUhljU7ogLQBQGJJRJIQEicBQFEyjCQEubMjsefO83y5s/Hk86/WNzRka4QrK9es/2TJsuz/ZHPnl2W25r2yL7fkzlLBM+iHv1y7cXO2nq9Ey52N+54cX3dAo+ei5cSJEx99uiTooRzkzgAAAAAAiUgS4vzbZgNAu8gwkhDkzo64yZ2NR5+ZGD6lXV+75Wc33WHHyh3JnY3Hx798pD5/8B05dzbMO27dvjNbNUQxc3717fcKPAma3BkAAAAAIBFJQkicBABFyTCSEOTOjjjLnY2f/ueoz75cdayxMVs1Xzl69NhHny7xHr4cY+5s/Or3oz9ZsmzPvv2Nx49np8mUjuTORs3Fl099/78OH6nPThBQTpw4sXrdxlvvHSOTC3JnAAAAAIBEJACAGJE7l61Lrxk5ZcaHGzZvOXyk3nvwsfmv+bf5i/m7eVXqdwo1F1/+1IRJy75as6/uQC5Yt5frZzfdIZMAAAAAAJCXRCQAgBiROwMAAAAAgDSSiAQAECNyZwAAAAAAkEYSkQAAYkTuDAAAAAAA0kgiEgBAjMidAQAAAABAGklEAgCIUWfKnbv2Gdi199lunSttABBGt77n+famUjtH2oBSMKOir+dLrM9AaQOAMLq5P2vqwzhcYtXDtc9Lr8cZQ7QZAIo6OXvr+doMhCMRCQAgRp0pd+7S6yxpfcn1OlPaACCMrr3P1b2p9KQNKIVTep4p3V5qXU47W9oAIAz3Z01detVIGxCz6uHS5w507zdYmwGgqJOztw7SZiAc6UkAQIzInQsidwYiIXcuV+TOQGdB7lyGyJ2BzoLcuVORngQAxIjcuSByZyAScudyRe4MdBbkzmWI3BnoLMidOxXpSQBAjMidCyJ3BiIhdy5X5M5AZ0HuXIbInYHOgty5U5GeBADEiNy5IHJnIBJy53JF7gx0FuTOZYjcGegsyJ07FelJAECMyJ0LIncGIiF3LlfkzkBnQe5chsidgc6C3LlTkZ4EAMSI3LkgcmcgEnLnckXuDHQW5M5liNwZ6CzInTsV6UkAQIzInQsidwYiIXcuV+TOQGdB7lyGyJ2BzoLcuVORngQAxKgz5c4V/S/s0X+ISxX9L5A2AAijsoq9tTyZfpaeL7WKqgulDQDCOBl7K+NwyUmfO1A54CJpA4AwZFdygL01MolIAAAx6ky5MwAAAAAAQFwkIgEAxIjcGQAAAAAApJFEJACAGJE7AwAAAACANJKIBAAQI3JnAAAAAACQRhKRAABiRO4MAAAAAADSSCISAECMyJ0BAAAAAEAaSUQCAIgRuTMAAAAAAEgjiUgAADEidwYAAAAAAGkkEQkAIEbkzgAAAAAAII0kIgEAxIjcGQAAAAAApJFEJACAGJE7AwAAAACANJKIBAAQI3JnAAAAAACQRhKRAABiRO4MAAAAAADSSCISAECMyJ0BAAAAAEAaSUQCAIgRuTMAAAAAAEgjiUgAADEidwYAAAAAAGkkEUniTV3d1NTUuGqs/P32edvN3+sW3SV/j+CNDfHMBwDInQEAAAAAQDpJRJJ4mdy5qWnZxEvsv9+3pKGpsWjuPGZuXdPqN+SPPuTOAOJD7gwAAAAAANJIIpLEm7q6qW7ZV7ua1k2tav3j04sONS37agu5M4CkIXcGAAAAAABpJBFJ4jXnznMnztvetOX1X2T/WDVxVdOhZY9aeXHV3TNX72nI3BjdVP/tsvG3XHLK/Yv2ef9vyrqpLXPLGDZq/PK6+sbmV+r3bHh9bi6/vmnsp1v2Zf7eVLdl1kNt7rD27rze/tWqffWZCo11mz6d+OPMS0OemLepLvvuZsK5T1/bXP+6iXO/sf44/qbAP/as/vH4RZvqMn80s509xkrYAXQy5M4AAAAAACCNJCJJvEzufP+1r29q2j57VOYvl4z/qql+ydOt9ylfN3NTY9O+pZNv+o/qqivHvLOpoal+1dhhpmbe+50veXSpqbDlnYeurer505smLmuOp5vnc8ldn9Y11a2aePtPTxl27V2zttTXb5jYknRnZJ740XbC7bNHezdfb5/79I//o/qU/7jp0SV1TTvnXdOzeuxXTU07F9115SXNc5u7y3tEdd4/Vj20aF9j3bLJo4f0vGTEQ7M31TesnpxJrgF0QuTOAAAAAAAgjSQiSTwvd64e8c6Wpp3zbjJ/+cXMTU27Zt3e+nyMa2bvajq07L7cJMMmL2tsWj3Z/Dtv7jyx+dU3Wu9lbn5UdPN8mmNl6ynS177zTS7p9jRX2DSzNRG+ae6upj2LRnr/O+zaK0c+PX7q7EXfenPLzLZ+y6xxD155Zdv38v1x4tdNTV9Nzt3jPGJm85Je0/K/ADoXcmcAAAAAAJBGEpEkXjZ3zqTJbQPolty5+T7lNk/SaI6b9306JiB3bplh7i/efO6ctz3zoAu71C99rrVa84QNi57I/W9mwqYNE3veNH55XVNjw75vNqxeMm/ikl1eq04ZNurRWcs27WlofqBHY93quZmHcuT54+hZO7Nv11oOLXs09y4AOhVyZwAAAAAAkEYSkSReLib2Hq8xddbOlpuOY77f2fy9YdHTuWp+Afc7P72svmnXO9dl/9h8t7KXO7e6ZMTTzQ/lWDYh/x/HmuVqE3AD6MTInQEAAAAAQBpJRJJ41u3JTy/L/Bhgyw8MtuTOp1w3dXV92+c7H1r2aMvznTdNbY2YMwKf79z89z3Lxt9p/p59zvKyCfa0zblz84SP3TSk509/PG7e9vrM852bc+e6RU83z+3Hj5mpvLk1P5C6ft3Mm5qfp2Eqm3dpWPRE3j9WV3lzmDh6xLBs++u/mshPCwKdFLkzAAAAAABII4lIEs/KnTO/4Nf6KORc7tyzuurumav3NDQ/oaKpad83i8be4uXF1078OvPHNk/hMG4av2RXJsJuaqrbMuvTljuUh41q/Xt93eqZY9qGv5n7nT+dt6kuU6GxbtOnmUdneM/ZyJT6PRtef6M5yN43/8FTrpu86Nvs35vnNvXB5rnl/WPPS655Zdl2s2imNDbsWzf7rubQHECnRO4MAAAAAADSSCIShNacO/ue2gEAbZA7AwAAAACANJKIBKGROwMojtwZAAAAAACkkUQkCI3cGUBx5M4AAAAAACCNJCIBAMSI3BkAAAAAAKSRRCQAgBiROwMAAAAAgDSSiAQAECNyZwAAAAAAkEYSkQAAYkTuDAAAAAAA0kgiEgBAjMidAQAAAABAGklEAgCIEbkzAAAAAABII4lIAAAxIncGAAAAAABpJBEJACBG5M4AAAAAACCNJCIBAMSI3BkAAAAAAKSRRCQAgBiROwMAAAAAgDSSiAQAECNyZwAAAAAAkEYSkQAAYkTu7NL1o95cumb7wfrGpmxpbNi/vXb+m2OHa808znli6f7maQ4ufvFOecmVv8+va27A/Mfk7+4lpyWdzCsbmrehNdP0753AY5ntv27paPl7u9355ubmTqjfPG/UCHmpQ9rRt9Nqm6tumJn9X120aJt3qZYLAAAAKGMSkQAAYkTu7Mg5o6Z92ZwlBZS6tRNGXSWTtDHilcWHTb2D88ddry+5Q+6cWGE7hNz5ig+2mdnUb5hzQ9zhbClz55lrmieofSX7v3mUbrkAAACAMiYRCQAgRuTOTtw8c01Dc27U1HhwzZxXbr22JWK+4s4HZ9Tu925/bqh95ea2U7W6atzqhqaGPR8+UTCbLrnkpL0PvLK0ds3ala/cJX9PLXLncO5ZuKOpaf/qaVfI3+PQjr4dN2/N2to1c17I/q8umn/zLpY7l3K5AAAAgDImEQkAIEbkzg6M+XBXc2gUmCy3pNL1q6ecIy8lC3cZJxa588kXvW+LL1rx+50BAAAARCARCQAgRuTOJXfOpLXNkVHTwfnBdytf9l7zd+Sbmra9eb2+lCTkzolF7nzykTsDAAAAnY5EJAkhjQSAomQYSQhy51K7ykujmjbPuUxfsoyYk3nga9OaN+XvD4ybX7vfe0aHKQ0H18yfIs9vzcw/Ezje/MKMtZkfLbQCrOEPz/ky90uGzT9juPbNh9s+ITrzqNn9i/9+as2dD87x3isovswfbhZ/i+bHW0/5cIP1g4oNB3esXTiu8COtCy2avyVX3fDywjV7cz3VVF+3x99XhrTEVPtyxtjhEvwF5oB547+2b216YEOeRYvWAxmF5+81qW3JPTjYJ382esXYN1fuyW1m2T6xKzS7ftSMtTvqrB7eu21xnmqtbp2/p7neroW36kvZnWLH/DHN/ysPO84pslK8bcCsi7YNy7ePGB3bEa664dl5rZObYuawdaXMoaVv/etr6Sv53ivU8529l9qWTCOzswqz98n6zdt4AAAAIJ0kIkkIaSQAFCXDSEKQO5falC8zkVDtjDAJY1s3t/4UYf3hhvpcbLR36WgrVsuGsy+2PELalGyAddXouXvqvb80NjTPIZuaNayZdmdu8pa4bcorG3LTa7LcIk/aG+otHlu4oyWwa65zOBfJ7ZlxT25WeQQvmrZktBdxmuI1I1d/+zw79LzixZW5FM9uSf3eg81LERhx5vhz5zsnrD7Y/DdTGqxFM22zb2+P2gMh5j/tS3uGmTr1K6e1nUkrf+58zhMLd7RM3Txt7t8bZloPC77tlbVt3yK3OCuDHw5zV/NDh5ua9nwoyzjC68ZtM7y7+zuUO+9Z4zWs7XqvXzvT+pinozvC6DltJ7fXgrWnZMP0DbVe5bY187xXqNz54YW11ny8edbOHZupFm65rm/dfbzJs//T1PDly+0flAAAAIDyIhFJQkgjAaAoGUYSgty5xLLRW5t8Kpy/z9/bPGX95nmjrsj+8ZxRUxZnHhVtx2qZtKuh/nCT/GjhZW9m8q/GPYtffqAlGbx+1JxtmaDKak8mAvPSqP1r5z1x323Bz5jWtDfkW7ziPWhk85zWu1CveMFbuqbV0wo80jpo0Xwtyd7zWzsj14zvDR+XvVH0y0ktU908pzYTzNld2nwr6NqWYLf9ufPoBZlpG7bNyN09OuKBcUszIXhD7SstT02J3AMh5+9fNUE0d24JJXcsbb1HePjD82ozf9y/oOW+2oe9zjy4eFzuJtmrbpjhBay+WLnVbW9ubq6Rva+5xTle6pr7BkCHcmdTGmrn/P2ybONzrWr3Vhq4I1zvfRehYc2MMa03d7esPvvWY69vTanfvvCJ1t8OHfNK9pMDfa9QuXP2L/4PPMIu1yhvE6pb+WBumx/xwJtetp7nVnQAAAAgXSQiSQhpJAAUJcNIQpA7l5iXKLWJkDzZqFRKLsbKPvHZH32OmPJlc2TUGva1pF3y/OgXFh9u/uuaabdZf2x269xMapmLO70ILPPWBQLQDInDQr7FWC+h2zHHugfTeCLTM4dXPmH/sa2ARTPatiSbiu6Z0fZnG0cvbk7c6pe/Yv9vc5dad4tn3Dlja/MrwRFnTtv4L5tI+lfuVeNWN6+klrw1ag+Enb8RMXd+cGkmf9xg3x2ccU/m85LGtRO8vnoz05DDa8e16bqrvFi59gPdAHKyDzdv05PZh2y0fh7QsdzZrN+22+1t3tpsWcYO7wjesu9aeIP9x9zmZDU7u7maFerbwLyOMpXbvFeHcuewy+V95qG3pWcf7NNyyzkAAACQVhKRJIQ0EgCKkmEkIcidSyxq7uylRTvmPmBNkvXE8kzm2PJSNu2S22a9KLZx7Tj7j57r5zVHTrmXvAgslzAWki/tDfEW2XCzqWHHyoUTxt7bcmtqcfkXrZkEc9kMrqlhz5fzpz34h7y3bD/wYeZW8bxdqvFoyNw5IJFs9uzK5ttOW16K2AOh5x81d84G4l++3FqhRTa9zb6UTcBNn9TOn/HKqJtDPxp4xLTMc2ashnkP2bC3tw7lzg2Ln22p36LNMpZkR7j+ioenLc50nT93zruBnfpyZgOT9+pI7hx6uVp+s7Rp/4alb04Ye0XurmcAAAAA5M4AyoUMIwlB7lxq2Xx5zTS5Y1d5t0+25M5e8FSwrJ7iTeilXXrPqRdsFSp7PrzLqrl1XqGfPcxqG4eFf4sRD0xYmbk5NFeaf1Vv6ZvPtj4WI6/8i9ZMg7lzRk370ssBW0rz7wounvNE6+/vZbu09RETtiIRZ06b+C97x2uBkosFI/VAO+afJ6nMr23unN04C5Rcijp83MJaL9z3SmND8+8Kzp/W+sSSAF7mXr/0Be9/vRg0dxN6Mwlhc0LlznkWuc0yxrMjXHXZE9M+XFpbu7f1wdbZ4sud829g2eftBDzSOkLuHH65aq5/cP62Ns1uaP5dwQ8nFfpNSAAAACAlJCJJCGkkABQlw0hCkDuXWvY223w37dqyDx9oyZ2zN6Jmf8Mtr5bfjsufdnm3yjZlf0ksn20fPpypGZT65dE2Dgv/Fp4r7hw1YaaEd/XbF/qeetEqOMjLnzkOv3nsE28uXLx2237rx9N2zPUem+BNEhALRsqds0/ObfmtuXzWTrAnb2cPtGf+gSGsaNulLblz8GbW8hN2nqsu+8MLEz5Y+uWGPftzHdx08MtJbZ8fIrzOPLzyweb/9Z743LB4nFUhaAssslICF7nNMnZ8R7j+lfneLmxmsnfbmrVr538w55UJY54IeM5G/g0s+yiY+HLn9u59I2779dhpMxavXbP9YGsGXbd2QttH0wAAAABpIxFJQkgjAaAoGUYSgty55C7L3pnof0ix5ebMV+N9z9ko8OTcnPxpl5dzFXx6clbk3Dn8W+Rx/a2TVmaSuKba9wKXsb25cxtXjJmw3LtfeNubzWFfoedsZB+DUDR39p5gkIv/vOwv1K3ifiF6oB3zj5Y7ex9v5HlURRjnXPv3GZsz8XM2Uw4yJtPzmazZe16H/Jxd0BboPUukg7lzh3eEcSszy7jV+i3KjKDnO8uPKGZ5G1huy+l47tyhve+qy57I/nRk7j50AAAAIJ0kIkkIaSQAFCXDSEKQOzvg5W5NTQ21b7Y+9sFyxQvZu5ut3Dn7xOGt866wazbL/ghe7sEdAeFsS9j3rL7jORLnRc6dw76FF5nl+QUzr+W5RfYLWDSjbUu8RciTz3pvna126/zM763l+9m3/L8r6Av1sr/Ylov/sg8v3ia/Z2hc8UHmobrZ35GL2gNh529Ey52zfeL7aT7z1q9kHpmdnaGXsbZ5OIbH6yg7D80n92wN7x+azOZffdnfTtSVUiiczWq7jB3cEbx38W+EV01Y3fx3u773vvk2sNuyL22ek13GjufOYZfLm1Wejxb8uTkAAACQQhKRJIQ0EgCKkmEkIcidnbh55hrvuQSNB9fMeeXWa1uioivufPDNld6Nh16xIsi/e2H0/rVzrBstr39w/p7mUKlh7biWbEuSxJzL3qzN1Nwz/+XWhwg3Pwc5k6PtmNuS/UXPnUO+hfdohab6zfNG5xa85nvDH55Xm/m+f74ftcsKWjRtSfZX7xpq5/zd+sm+60fNyYSzuYcgX59dC/Xbl47LfQBwxZhXVnu3RVvBn/fbd2YRFrzQ8gzc6299c20mYzWlNf4b7T0Ko672zYdbf2pv+LiFO5rfqOHLl713id4D4eZvBMaLQrs02ycNOxZPuSHXdSMemOD1Se7G5HGZKLPp4OJJY1ofCjzigXHeQ6vz/vKhzVtBh9d+2dwP3u3nlmx43fDl6y1b0YjbnvC2c1NyKyVi7tzBHSF7m3z9hjmt/XPFmAlLvU8g8uXOzRvYwidyK9r0Uray9Y2HiLlzm48uQi5X9jct966ccE/rJnTOqCkt1fLd/g8AAACkhkQkCSGNBICiZBhJCHJnV26eMn9rJgDKV+q3LnxiRnMU1ebW11xabSp4z2zNPpj14OJnb8tVCw5nrxq9oCUd854RnJvb5jmtDzroQO4c8i3OeWLpjmzLm7KPEs5VWzvTd0N3q7C5s90M7auGNdNanz7sb4n3z/0btrUN/q5q/U0/b7m8qXbVrml+X/u20ztfWduyMG0Xbf/SV3I38EbugZDzP7Xmtuwt215rW5797efvUrttzdPmHo3dsO3Ne3LVrGa0PG+65X/3FHqATFbL3cGm5O75bXXnKxvaLKP3z/q1tc2bZodz5w7uCNl415Q2C96wY3t2CzE776hMTe999+9t2XKsZTH/U/vB2Fw63P7c2bv9PNuGloduh1suaxiRTahp19ICT1cHAAAA0kAikoSQRgJAUTKMJAS5s0tX3fDsvMVbD7bmPg0N+7eunPFs5nbFzLOD9ZELV4x9ZXFt62+4NTbs37Cw9V7djOBw1mh+xy+tXxKrr9vz5YyxrbesGh3KnY0Qb9F8f+UrM1ZaP0bX2FC/t3b+m1pNhM6dDW1Gc99uWPqKdZtw1s0v2C3JtlaDP+P6UTOsnm84uGb+lBtGeO8rj5W4ftSbS9fszVVtMov2oXULqidaD2SEm/8TC2ub25YpwWszb5dq2xoO7lhp32XvyTbD6mFTbd4TeR8d4+c9/KGp6ctJ+eqPeGDc4m26UrybfGPInY2O7AhX3fDywtb+b94HM9vV9VMWex2+q03uvGbaVaNet9aXqb99rX27erN2587fu2LS2lz/WKNEqL0vO4y0huCZanNeab2DGwAAAEgriUgSQhoJAEXJMJIQ5M6AP/gDAAAAAJQ/iUgSQhoJAEXJMJIQ5M4AuTMAAAAApJFEJAkhjQSAomQYSQhyZ4DcGQAAAADSSCKShJBGAkBRMowkBLkzQO4MAAAAAGkkEUlCSCMBoCgZRhKC3BkgdwYAAACANJKIJCGkkQBQlAwjCdGZcuceZwzp3u98l3qccb60AalSOWCYbBIOVFYPk2YEkQkdqOh/gbQBadPDt1WUWkX/IdIGpIoZdmSTcEDaEMQM1zKhA5UDLpJmIFVke3CgcsBQaQNSJcnXX5VVQ2VaByqrh0szUAYkIkkIaSQAFCXDSEJ0pty5S6+zpPUl1+tMaQNSpaL/hbpJlF5F1YXSjPyqh8uEDnTtM1CbgZQ5peeZslWUWpfTzpY2IFW69R0om0Tp1UgbglQOGOqbtuS6h47FUYZOxqG/e7/B2gykSZfTknv91eOMwTpt6VXw4V85krWcENJIAChKhpGEIHcuiNw53cidBbkzyJ3hGLmzIHdONXJnOEfuLMidy5Ks5YSQRgJAUTKMJAS5c0HkzulG7izInUHuDMfInQW5c6qRO8M5cmdB7lyWZC0nhDQSAIqSYSQhyJ0LIndON3JnQe4Mcmc4Ru4syJ1TjdwZzpE7C3LnsiRrOSGkkQBQlAwjCUHuXBC5c7qROwtyZ5A7wzFyZ0HunGrkznCO3FmQO5clWcsJIY0EgKJkGEkIcueCyJ3TjdxZkDuD3BmOkTsLcudUI3eGc+TOgty5LMlaTghpJAAUJcNIQpA7F0TunG7kzoLcGeTOcIzcWZA7pxq5M5wjdxbkzmVJ1nJCSCMBoCgZRhKC3Lkgcud0I3cW5M4gd4Zj5M6C3DnVyJ3hHLmzIHcuS7KWE0IaCQBFyTCSEJ0pd+7W97vd+pzrVF9StlSrqBqqm0TpVYY9nR0uEzrAxSe69RkoW0XJ9T1P2oBUMcOObhIlF/bQX1l9kW/akqvof4E0AylSfRIO/T3Y5NItyddfZuPUaUuvcsAwaQbKgEQkCSGNBICiZBhJiM6UOwMAAAAAAMRFIpKEkEYCQFEyjCQEuTMAAAAAAEgjiUgSQhoJAEXJMJIQ5M4AAAAAACCNJCJJCGkkABQlw0hCkDsDAAAAAIA0kogkIaSRAFCUDCMJQe4MAAAAAADSSCKShJBGAkBRMowkBLkzAAAAAABII4lIEkIaCQBFyTCSEOTOAAAAAAAgjSQiSQhpJAAUJcNIQpA7AwAAAACANJKIJCGkkQBQlAwjCdGZcufKAcPckzZ0UrJQLlRfJG0AkqL6JOwRp1YP12YgXYbLJuGAeVNfM5Aisj24EP7QX31S9ghfMwLIhA5wjCi1ymrtcwekDUgb2R5cqA671emETkgbglSejAOERCQJIT0DAEXJMJIQnSl37tLrLGl9yfU6U9rQSXXpVaOLVmJde58tbQASonLAUNlcHehxxhBpBlKlcsBFskk4wFaXcu7PmszJhrQhSPd+g2RaByrDpR4naW89X5qBeHXv+13pcwekDUiX6uGyPThghlZtRoAuvc6UaUuty2lnSRuCdD/9JBwgkkl6BgCKkmEkIcidCyJ3jorcGYlF7gz3yJ3hHrmzIHdOM3JnuEbu3Ba5cwTSMwBQlAwjCUHuXBC5c1Tkzkgscme4R+4M98idBblzmpE7wzVy57bInSOQngGAomQYSQhy54LInaMid0ZikTvDPXJnuEfuLMid04zcGa6RO7dF7hyB9AwAFCXDSEKQOxdE7hwVuTMSi9wZ7pE7wz1yZ0HunGbkznCN3LktcucIpGcAoCgZRhKC3LkgcueoyJ2RWOTOcI/cGe6ROwty5zQjd4Zr5M5tkTtHID0DAEXJMJIQ5M4FkTtHRe6MxCJ3hnvkznCP3FmQO6cZuTNcI3dui9wZAFKL3LkgcueoyJ2RWOTOcI/cGe6ROwty5zQjd4Zr5M5tkTsDQGp1pty5W5+BXXuf41K3PudKGzopsyCyaKXW7fTvShuAhKisvkg2Vwcqqi6UZiBVKgcMk03CAba6lOvWN7lnTT36ny/TOlBZHS53rj4Ze2v/C6QZ+P+3d/8hct53guf/uL/3T0vqH17uljs4S7alVnfLin/phy11M+yhO3O+PZtwBAYWxweLWMI4DAFf2BByNjebGTYZ5g/NZVjBnHXGiRZnEasZ7Y7GmfFFYydpb86SBiF1xhJSrDGiHeHusU1vPVXdUvWnVVa7/K1vPVXfl3lhWtX1VH36eZ56qvTWw9Npje7YG9Z5r225/+EwA2WZng27RAYb/xesPvzd8MGN/t2w8VOEZTMIiQSAhAapOwMAAACkEhIJAAnpzgAAAECJQiIBICHdGQAAAChRSCQAJKQ7AwAAACUKiQSAhHRnAAAAoEQhkQCQkO4MAAAAlCgkEgAS0p0BAACAEoVEAkBCujMAAABQopBIAEhIdwYAGDbjUwfHpg7kND51IMzQyfj0TFg2gzDDZwgLZtBYIWEGYNCFl3kGGz+S9OMN4mCYoZO+vEGERAJAQrozAMCw2bR1d/jM12ubtu4KM3QysmNPWDaD8akNFZnxqYNhwQxGJ/aFMYDBNj0bXuYZNA6tcYwONm19KCzba5u27Q4zdDKyvQ9vEAD0ju4MADBsdOdAdwby0Z3X0p0BiqU7AwAMG9050J2BfHTntXRngGLpzgAAw0Z3DnRnIB/deS3dGaBYujMAwLDRnQPdGchHd15LdwYolu4MADBsdOdAdwby0Z3X0p0BiqU7AwAMG9050J2BfHTntXRngGLpzgAAw0Z3DnRnIB/deS3dGaBYujMAwLDRnQPdGchHd15LdwYolu4MAAAAlCgkEgAS0p0BAACAEoVEAkBCujMAAABQopBIAEhIdwYAAABKFBIJAAnpzgAAAECJQiIBICHdGQAAAChRSCQAJKQ7AwAAACUKiQSAhHRnAAAAoEQhkQCQUOzO41MHc5ueCTMAFCseIbMIM1CasD/k4K2/cNMzcZfovThDZ2HBDO6dng0zUJLZsD/kYJcrW9wfsggzdNSPN4iQSABIaE13bvw9MHw7gy3bH2ufAaBkm7Y+FA6SvdZ4xjADpQm7RAab7384zEBRRnbsCbtEBuNTG/rXjr4EiNGJfWEMytGnXW5vGIOi9OHT5rbdYYZORrb34Q0CgN7RnQFqRHcmv7BLZKA7F053DnTnkunO5Kc7A5CN7gxQI7oz+YVdIgPduXC6c6A7l0x3Jj/dGYBsdGeAGtGdyS/sEhnozoXTnQPduWS6M/npzgBkozsD1IjuTH5hl8hAdy6c7hzoziXTnclPdwYgG90ZoEZ0Z/ILu0QGunPhdOdAdy6Z7kx+ujMA2ejOADWiO5Nf2CUy0J0LpzsHunPJdGfy050ByEZ3BqgR3Zn8wi6Rge5cON050J1LpjuTn+4MQDahO8/e03gTymtk++PtMwCUrPG5PBwke23jfxNgWFV//8xrywOPhBkoyuiOvWGXyGB8esPded2yvTY6sT+MQTn6tMv5p46i5f+0ufF/b67+YXLd4j23rpIAkMqa7gwAAABQiJBIAEhIdwYAAABKFBIJkMS+r58is7AJakJ3BgAAAEoUEgmQREiiZBA2QU3ozgAAAECJQiIBkghJlAzCJqgJ3RkAAAAoUUgkQBIhiZJB2AQ1oTsDAAAAJQqJBEgiJFEyCJugJnRnAAAAoEQhkQBJhCRKBmET1ITuDAAAAJQoJBIgiZBEySBsgprQnQEAAIAShUQCJBGSKBmETVATujMMpunZe+7bldmWBx+NYwCUanzqYDhIZjA6sS+MAVCmxvEwHCEzaBz5wxgMgZBIgCRCEiWDsAlqQneGwVR15/h67rXND+jOACvGpw6Eg2QGIzt0Z4DK6MTecITMYEx3HkZhKwNJhCRKBmET1ITuDINJdwboK90ZoI90Z1IJWxlIIiRRMgiboCZ0ZxhMujNAX+nOAH2kO5NK2MpAEiGJkkHYBDWhO8Ng0p0B+kp3Bugj3ZlUwlYGkghJlAzCJqgJ3RkGk+4M0Fe6M0Af6c6kErYykERIomQQNkFN6M4wmHRngL7SnQH6SHcmlbCVgSRCEiWDsAlqQneGwaQ7A/SV7gzQR7ozqYStDCQRkuhGfP0vrl/6zafLrf8+/vjS2V996+V4Hz5D2AQ1oTvDYJqevWfrrsy2PKg7A6wYnzoYDpIZjE7ozgCVxvEwHCEzaBz5wxgMgZBIgCRCEr2rZ//8xofN4Ly09GlD88vlpatX/uW6ew6gK5eqn+bmj+PtiYVNUBO6MwAAAFCikEiAJEISvatXrjRD8/yl1h+f/fcfNDP0R6ePrLnbYNKdAQAAAAoTEgmQREiid9Xqzssf3Tz9H899/d/E7+57+dyf/d3Sh63ToD/++NLb554Nd6j89Mh/vvnhx837fPrxlQu3L9Px7I+unr/R+kbjKZZ++de/bC3+hxeqG69cuH7lo+a3Pv30yv//t81vNUvxRx+++Xcfr5x7/ZsPf/gnK4/Wfj2QDz/44JXV2/e9/MsfXlwz5D9v3Ph6K6Cv/Pfhhb/t/AitJ/3gh2/frB7k11dWHnbDwiaoCd0ZAAAAKFFIJEASIYne3Z9cubRahqv/Pv740oUrv78SoH/x419XlXZp4ealqzf/vnm3K3O/WLP410/94fnmNz5eatyn1ZGX5i9VEflPrl6plv7073/dWPyjZhf+9NJPf1Yt0uzOK9/6oPX10puvNB6tdYby8vJHH916xuUrv2ossnIi9qcfX7m6usjSjX9bBe6f/fhqMyW3LVINeeRvf/j2jb+v/rT0y7ev/vDf/6zzI6w+aes/3RkAAABgcIVEAiQRkuiGvPyzP/zJ9V/+emnlnOXGfx/f/PGR1VOGF66/3Lzbs3/x4VLjj7/54Pfbl/36r8430/Sb/2/zj0d+XZ0//emHr6zG5aWLF1r3fPYnzfOPF65/69a3/u5XzXOc//btZq0+/5eNr1sJeOl080zkZ//mZvWnapG/+vGvqy/P/+Svmo/2i9M3qj9e+umpfa9cr+Lypx/+sHWS9Z/fqIZsPsvqo7Wus9H5EVa784cXLv3Lrn6hYtgENaE7AwAAACUKiQRIIiTRz+uf/7tfX1k5Zfhn+1rZd6k6kfm2i1eaSfeWZrRdunFkzY2VVue99Dert7Qq9kcf/OFqd25d+2LtPdtLcfsiK236w+ttk1y9efo/rN7n+tXq2hpR+6N1foSVu330Z11F54awCWpCdwYAAABKFBIJkERIonfTOlt5+dJf/3T1lnffXKhuufL2X7WX4rZFgla0XTlDed/LzT+2n+/cuubGnc53/jzdeeVs5Ut/0zpbuc2/a95n6cNXWtW4tUjn853v8AjhST+/sAlqQncGAAAAShQSCZBESKJ381etBNz4b2np00ozQy9/3Mq4Kw26dX3nSzeq7314fiUWx0doXl75c13f+fN051PP/mXzKh+tqzO3Hq11MZDPugh169GqAX750192fgTdGQAAAGBYhEQCJBGS6Ab89Pff/vDvP6rSbfXfp59+ePXXR1onLze8fO7P/m6pmYybxfbCr75+e8FbfvHK2Zsr14Zu3udbqxesePZHV8/fWOnayx999PZf/rJ17nMX3bnxx6//xfVLv1mZc+k3N//sR6tnLrcP+fHHl94+t3rNjZ+9Mr/y7K3n6vAIujMAAADAsAiJBEgiJFEyCJugJnRnAAAAoEQhkQBJhCRKBmET1ITuDAAAAJQoJBIgiZBEySBsgprQnQEAAIAShUQCJBGSKBmETVATujMAAABQopBIgCRCEiWDsAlqQncGAAAAShQSCZBESKJkEDZBTejOAAAAQIlCIgGSCEmUDMImqAndGQAAAChRSCRAEiGJkkHYBDWhOwMAAAAlCokESCIkUTIIm6AmdGcAAACgRCGRAEmEJEoGYRPUhO4MAAAAlCgkEiCJkETJIGyCmtCdAQAAgBKFRAIkEZIoGYRNUBO6MwAAAFCikEiAJEISJYOwCWpCdwYAAABKFBIJkERIomQQNkFN6M4AAABAiUIiAZIISZQMwiaoCd0ZAAAAKFFIJAAkpDsDAAAAJQqJBICEdGcAAACgRCGRAJDQIHXn/+7AV+77p/97ZmEGAAAAYDiERAJAQoPUnQ9+6z89e+wfMgszAJTsnvseCu8ivbZp25fCDMBGbNq6O7yaem3T1l1hBhKbng3rPIORHXvjGMBd9efVuieOwcaENQlAQrrzXYQZAEqmO8Og0J2HkO4Mg0J3HihhTQKQkO58F2EGgJLpzjAodOchpDvDoNCdB0pYkwAkpDvfRZgBoGS6MwwK3XkI6c4wKHTngRLWJAAJ6c53EWYAKJnuDINCdx5CujMMCt15oIQ1CUBCuvNdhBkASqY7w6DQnYeQ7gyDQnceKGFNApCQ7nwXYQaAkunOMCh05yGkO8Og0J0HSliTACSkO99FmAGgZLozDArdeQjpzjAodOeBEtYkAAnpzncRZgAome4Mg0J3HkK6MwwK3XmghDUJQEKD1J0B6K/x6Zn8wgzARoTXUR5hBpILKzyDe6dnwwzARoSXUgZerV0LiQSAhHRnAAAAoEQhkQCQkO4MAAAAlCgkEgAS0p0BAACAEoVEAkBCujMAAABQopBIAEhIdwYAAABKFBIJAAnpzgAAAECJQiIBICHdGQAAAChRSCQAJKQ7AwAAACUKiQSAhHRnAKCmRrY/vvn+L+X1cJihk/Gpg+uW7bnRnU+EMQB6Z/MDj4SjUO9t9CA8unP/umV7rnHkD2MwBEIiASAh3RkAqKktDz4aPrj03q4wQyfjUwfWLdtzIzv2hTEAemfTtt3hKNRzWx8KM3QyOrE3Ltt7Y7rzMApbGYCEdGcAoKZ050B3BnLSnQPdeSiFrQxAQrozAFBTunOgOwM56c6B7jyUwlYGICHdGQCoKd050J2BnHTnQHceSmErA5CQ7gwA1JTuHOjOQE66c6A7D6WwlQFISHcGAGpKdw50ZyAn3TnQnYdS2MoAJKQ7AwA1pTsHujOQk+4c6M5DKWxlABLSnQGAmtKdA90ZyEl3DnTnoRS2MgAJ6c4AQE2NT8+OT89kFmboaLoxXly292bjGAA904eD8FStD8JxBoZCSCQAJKQ7AwAAACUKiQSAhHRnAAAAoEQhkQCQkO4MAAAAlCgkEgAS0p0BAACAEoVEAkBCujMAAABQopBIAEhIdwYAAABKFBIJAAnpzgAAAECJQiIBICHdGQAAAChRSCQAJKQ7Q0djkwc23/+lzMamDoQx7mx6NiyYwZbtj8cxAHppZPuecCDqvYfDDJ2MTx1ct2zPje7cH8YA6J0tDzwajkK990iYoZPG8XDdsj3XOPKHMRgCIZEAkJDuDB2N7XwyvGAyGJt8MoxxZ9OzYcEMNj/waBwDoJe2PPhoOBD13q4wQyfjUwfWLdtzIzv2hTEAemfTtt3hKNRzWx8KM3QyOrE3Ltt7Y7rzMApbGYCEdGfoSHcOdGcgM9050J2BnHTnQHceSmErA5CQ7gwd6c6B7gxkpjsHujOQk+4c6M5DKWxlABLSnaEj3TnQnYHMdOdAdwZy0p0D3Xkoha0MQEK6M3SkOwe6M5CZ7hzozkBOunOgOw+lsJUBSEh3ho5050B3BjLTnQPdGchJdw5056EUtjIACenO0JHuHOjOQGa6c6A7AznpzoHuPJTCVgYgId0ZOtKdA90ZyEx3DnRnICfdOdCdh1LYygAkpDtDR+PTM6M7n8hsfHo2jNFJWDCDsckDYQaAnmocdsKBKIMwQ2ezYcEMxiUPIKOxdUehDMIMnTSOh2HBDO7d8Ad1BkhIJAAkpDsDAAAAJQqJBICEdGcAAACgRCGRAJCQ7gwAAACUKCQSABLSnQEAAIAShUQCQEK6MwAAAFCikEgASEh3BgAAAEoUEgkACenOAAAAQIlCIgEgId0ZAAAAKFFIJAAkpDsD1MjmBx7ddP/DOTWeMcwA0FOjE/vDgSiD8emZMMYdNe4WFsxgdOcTYQyA3tn8wCPhKNRrmx98LMzQSV/eIEIiASAh3RmgRjZtfSgcpnut8YxhBoCeGtmxJxyIMhif2lh3njoYFsxgdGJfGAOgd/rwaXPb7jBDJyPb+/AGAUDv6M4ANaI7A0NPdw50ZyAn3RmAbHRngBrRnYGhpzsHujOQk+4MQDa6M0CN6M7A0NOdA90ZyEl3BiAb3RmgRnRnYOjpzoHuDOSkOwOQje4MUCO6MzD0dOdAdwZy0p0ByEZ3BqgR3RkYerpzoDsDOenOAGSjOwPUiO4MDD3dOdCdgZx0ZwCy0Z0BamRs5xOjE/tzajxjmAGgp8anDoQDUQb3Ts+GMe5sejYsmMH41ME4BkDPjO2MR6Fe2/inzb68QYREAkBCujMAAABQopBIAEhIdwYAAABKFBIJAAnpzgAAAECJQiIBICHdGQAAAChRSCQAJKQ7AwAAACUKiQSAhHRnAAAAoEQhkQCQkO4MAAAAlCgkEgAS0p0BAACAEoVEAkBCujNQmOmZkR17MhufOhjH6GB0x96R7XtyajxjmAGgp8YmnwwHyQzunZ4NY9zR+PRsOEhmMD55IIwB0DsjjU+b6w6SPTU6sdFPm9UbxLqDZK+FRAJAQrozUJbxqQPhOJjB6MT+MEYnm7Y+FJbttcYzhhkAempkRx/+kj8+NRPGuKPxqYNhwQxGJ/aFMQB6pw+fNrftDjN0ogIDDBndGSiL7hzozkBmunOgOwM56c4AZKM7A2XRnQPdGchMdw50ZyAn3RmAbHRnoCy6c6A7A5npzoHuDOSkOwOQje4MlEV3DnRnIDPdOdCdgZx0ZwCy0Z2BsujOge4MZKY7B7ozkJPuDEA2ujNQFt050J2BzHTnQHcGctKdAchGdwbKojsHujOQme4c6M5ATrozANnozkBZxqdnRnbszWxs6mAYo5PRiX1h2V4bndgbZgDoqbHJJ8OBKIPx6dkwxp1Nz4YFMxifOhDHAOiZ0XVHoV7b+L+u9eUNIiQSABLSnQEAAIAShUQCQEK6MwAAAFCikEgASEh3BgAAAEoUEgkACenOAAAAQIlCIgEgId0ZAAAAKFFIJAAkpDsDAAAAJQqJBICEdGcAAACgRCGRAJCQ7gwAAACUKCQSABIapO78Pz+2+1/s2ZFZmGFAje7YO5LX6MT+MANAT41NPhkORBncu2s2jHFH49OzYcEMxqcOhjEAemd0x75wFOq1jX/aHNvZlzeIOAZQTyGRAJDQIHXnH8+MLv+P/1VmYYYBtWnrrrDhe23z/V8KMwD01Jbtj4cDUQbj0zNhjDsanzoYFszAv/8BOW3a+lA4CvXapg1/2hx58LGwbAZhBqC2wosXgIR057sIMwwo3RkYerpzoDsDOenOQZgBqK3w4gUgId35LsIMA0p3Boae7hzozkBOunMQZgBqK7x4AUhId76LMMOA0p2Boac7B7ozkJPuHIQZgNoKL14AEtKd7yLMMKB0Z2Do6c6B7gzkpDsHYQagtsKLF4CEdOe7CDMMKN0ZGHq6c6A7AznpzkGYAait8OIFICHd+S7CDANKdwaGnu4c6M5ATrpzEGYAaiu8eAFISHe+izDDgNKdgaGnOwe6M5CT7hyEGYDaCi9eABIapO78gwP/9aV/+o8yCzMMqC0PPrr5gUdyGtn+eJgBoKdGJ/aFA1EG907PhjHuaHx6JiyYwdjkk2EMgN7ZnP3T5pYNf9oc3dGPN4h1YwD1FBIJAAkNUncGAAAASCUkEgAS0p0BAACAEoVEAkBCujMAAABQopBIAEhIdwYAAABKFBIJAAnpzgAAAECJQiIBICHdGQAAAChRSCQAJKQ7AwAAACUKiQSAhHRnAAAAoEQhkQCQUOjOs6MT+zIbmzywdgbKMjb5ZNglMggzQH2MT82E3TWD8enZMAZFCftDBmOTT4QZoCbGJw+E3TWDex2ESzbdj79/TR2MY0DBQiIBIKE13Xl8eiZ8O4Mt2x9rn4HSbHng0bBLZOAveNTW2OSTYXfNQAQsXNgfMth8/8NhBqiJke17wu6aQeMTeBiDcoxPHQz7QwajE3vDGFCy8AIBICHdmT7TnaGd7kx+YX/IQHemtnRnMtOdoe/CCwSAhHRn+kx3hna6M/mF/SED3Zna0p3JTHeGvgsvEAAS0p3pM90Z2unO5Bf2hwx0Z2pLdyYz3Rn6LrxAAEhId6bPdGdopzuTX9gfMtCdqS3dmcx0Z+i78AIBICHdmT7TnaGd7kx+YX/IQHemtnRnMtOdoe/CCwSAhHRn+kx3hna6M/mF/SED3Zna0p3JTHeGvgsvEAAS0p3pM90Z2unO5Bf2hwx0Z2pLdyYz3Rn6LrxAAEhoTXe+d3p28wOPZDY6sW/NDBRmdMfesEtkcO8u3ZmaGps6EHbXDManDoQxKErYHzIY2b4nzAA1MTqxP+yuGejOJRufmgn7QwZjO/17M9wWEgkACa3tzgAAAABlCIkEgIR0ZwAAAKBEIZEAkJDuDAAAAJQoJBIAEtKdAQAAgBKFRAJAQrozAAAAUKKQSABISHcGAAAAShQSCQAJ6c4AAABAiUIiASAh3RkAAAAoUUgkACQ0UN15amZ86kBW0wfiDB2M7ti3+YGHM7t3Oo5xR2M7nwgLZnDv9GwYg8Jkf7VOHVw3A+k11vO6Nd9b9+7a8JbN/x7RGG9jx+GR7XvCQTIDx+HC/TePP/1P9vwvef2zMAPJhUNQBo039DBDJ2HBLDb+1t+PN4g4A2UJ+0MG3ve7FhIJAAkNUne+575dYfoMwgydbHnwkbBgBmOTT4Yx7mhkx56wYAab7/9SGIOibNr6UNglMggz0AthnWexK8zQyeYHHl63bM9tsHpsvr8Ps41O7A9jUJT/6Y8uPXvsH3L6Z/92IcxAYtOz4WWewcj2x+MYHdyzNfcH9U3bdocZOtnyQB8+qIcZKMp4vV+tBGFNApCQ7nwXYYZOdOdAdy6c7jyswjrPQnfuku5cON15COnOa+nO1JbuPFjCmgQgId35LsIMnejOge5cON15WIV1noXu3CXduXC68xDSndfSnakt3XmwhDUJQEK6812EGTrRnQPduXC687AK6zwL3blLunPhdOchpDuvpTtTW7rzYAlrEoCEdOe7CDN0ojsHunPhdOdhFdZ5Frpzl3TnwunOQ0h3Xkt3prZ058ES1iQACenOdxFm6ER3DnTnwunOwyqs8yx05y7pzoXTnYeQ7ryW7kxt6c6DJaxJABLSne8izNCJ7hzozoXTnYdVWOdZ6M5d0p0LpzsPId15Ld2Z2tKdB0tYkwAkpDvfRZihE9050J0LpzsPq7DOs9Cdu6Q7F053HkK681q6M7WlOw+WsCYBSGiQuvOmrbs3bd2V1baHwgydjO7ct/n+hzMbmzwQxrij8amDYcEMtjz4WBiDomze9nB8NfXcRl+tfBGN9bxuzffYxrPC9kfjsr03PjUTxrijsZ37w0Eyg7GdT4QxKMqT/8d/+K3/662cZv/Pvw4zkNj0bDgEZTCyY28co4PG4Tos22sbP8thy4P53yB8LCnaeH9erXvCGGxQSCQAJDRI3RkAAAAglZBIAEhIdwYAAABKFBIJAAnpzgAAAECJQiIBICHdGQAAAChRSCQAJKQ7AwAAACUKiQSAhHRnAAAAoEQhkQCQkO4MAAAAlCgkEgAS0p0BAACAEoVEAkBCujN0Nj07Nnkgs8aTxjHurA+zjU/PrBvjzsanDo437p/T1IEwQ2ezcdne2/Bmba66qerHyehgmOEzNO4c9ooMwgwUZXxqJryaeq7eB5PhOA7/k73/63//W89l9o93/w9hjE7aDo+5bPw9IqzzDDa8yzGU+nEk2ejHksYLJy7be40jfxijk7BgDrV+g9j4Zp2JR8jeC4kEgIR0Z+hobPLJ8ILJoPGkYYw7anx6CwtmMDqxL4zRyeb7HwnLZhBm6KQvHy5HJ/aHMTrZtPWhsGyvNZ4xzPAZNm/bHRbPIMxAUbY8+GjYH3pvV5ihk74cTEZ2bPQ4vGlr7lfrpq0bXXWP/Iv/+9lj/5DZf/vk/xbGuKNav71Oz4YFMxjZsTeOQUk25X/f3/DHktGJvXHZ3hvbYD/tz6t1Txyjgz582ty2O8zQycj2PWFZAAaa7gwd6c6B7tw13fmLCDNQFN050J27pjt3R3cunO4c6M7d0Z0BiqU7Q0e6c6A7d013/iLCDBRFdw50567pzt3RnQunOwe6c3d0Z4Bi6c7Qke4c6M5d052/iDADRdGdA925a7pzd3TnwunOge7cHd0ZoFi6M3SkOwe6c9d05y8izEBRdOdAd+6a7twd3blwunOgO3dHdwYolu4MHenOge7cNd35iwgzUBTdOdCdu6Y7d0d3LpzuHOjO3dGdAYqlO0NHunOgO3dNd/4iwgwURXcOdOeu6c7d0Z0LpzsHunN3dGeAYunO0JHuHOjOXdOdv4gwA0XRnQPduWu6c3d058LpzoHu3B3dGaBYujN0pDsHunPXdOcvIsxAUXTnQHfumu7cHd25cLpzoDt3R3cGKJbuDABATr/1jx/Kbd0MAFAJiQSAhHRnAAAAoEQhkQCQkO4MAAAAlCgkEgAS0p0BAACAEoVEAkBCujMAAABQopBIAEhIdwYAAABKFBIJAAnpzgAAAECJQiIBICHdGQAAAChRSCQAJKQ7AwAAACUKiQSAhAapO29+4JHN276U1f0PhxmgJsanZjZt253Z6M79YQwA+LzGJp+Mn7h6b2zqYBgDABpCIgEgoUHqzpu27g7T99zWh8IMUBPjUwfj7tp7oxP7whgA8HmN7nwivL9kMDZ5IIwBAA3h/QKAhHTnz6Q7U1e6MwADSncGoD7C+wUACenOn0l3pq50ZwAGlO4MQH2E9wsAEtKdP5PuTF3pzgAMKN0ZgPoI7xcAJKQ7fybdmbrSnQEYULozAPUR3i8ASEh3/ky6M3WlOwMwoHRnAOojvF8AkJDu/Jl0Z+pKdwZgQOnOANRHeL8AICHd+TPpztSV7gzAgNKdAaiP8H4BQEKD1J3v3TV773R2cQYAAL6Y8HErgzAAADSFRAJAQoPVnQEAAADSCIkEgIR0ZwAAAKBEIZEAkJDuDAAAAJQoJBIAEtKdAQAAgBKFRAJAQrozAAAAUKKQSABISHcGAAAAShQSCQAJ6c4AAABAiUIiASAh3RkAAAAoUUgkACSkO6cxtvOJLdv3ZBZmILnxqZmwzjMYnzoYxgAG3ejE/vBKzyDMAACf1+jEvvDmkkGYAXotJBIAEtKd0xh58LGwZjMIM5Dc2OSTYZ1n0HjSMAYw6Dbf/3B4pWcQZhhQozv3j+zYm1mYgaKMT8+E/SED/+RMbW3e9qXw5pJBmAF6LeyBACSkO6ehOw8l3RlIQnfu2ub7Hwk/V89t3RVmoCjjkwfiLtF7ozufCGNATejOlCDsgQAkpDunoTsPJd0ZSEJ37pruTGa6M7TTnSlB2AMBSEh3TkN3Hkq6M5CE7tw13ZnMdGdopztTgrAHApCQ7pyG7jyUdGcgCd25a7ozmenO0E53pgRhDwQgId05Dd15KOnOQBK6c9d0ZzLTnaGd7kwJwh4IQEK6cxq681DSnYEkdOeu6c5kpjtDO92ZEoQ9EICEdOc0dOehpDsDSejOXdOdyUx3hna6MyUIeyAACenOaYxO7N/y4KOZhRlIbnzqYFjnGTSeNIwBDLrRHXvDKz2DMMOA0p3JTHeGdiPb94Q3lwzCDNBr4ZgMQEK6MwBQU1XyeOCRvCSPoo1PzazbJXpubPJAGAOAbEIiASAh3RkAAAAoUUgkACSkOwMAAAAlCokEgIR0ZwAAAKBEIZEAkJDuDAAAAJQoJBIAEtKdAQAAgBKFRAJAQrozAAAAUKKQSABISHcGAAAAShQSCQAJ6c4AAABAiUIiASAh3TmNkQcfC2s2gzADRRmfOhj2hwxGJ/aFMSjN5m27w16RQZgBAD6vTVsfCm8uvdZ4xjADUE/hxQtAQrpzGrozmenO9IXuDLdsqd76d2W1dVeYgeSab6/r1nyPje58IoxBcroz0El48QKQkO6chu5MZrozfaE7wy3N7hx3114LM5Dc+OSBsM4z0J0z0J2BTsKLF4CEdOc0dGcy053pC90ZbtGdh5LuPKx0Z6CT8OIFICHdOQ3dmcx0Z/pCd4ZbdOehpDsPK90Z6CS8eAFISHdOQ3cmM92ZvtCd4RbdeSjpzsNKdwY6CS9eABLSndPQnclMd6YvdGe4RXceSrrzsNKdgU7CixeAhHTnNHRnMtOd6QvdGW7RnYeS7jysdGegk/DiBSAh3TkN3ZnMdGf6QneGW3TnoaQ7DyvdGegkvHgBSEh3BgD43HTnoaQ7A5QmHJMBSEh3BgAAAEoUEgkACenOAAAAQIlCIgEgId0ZAAAAKFFIJAAkpDsDAAAAJQqJBICEdGcAAACgRCGRAJCQ7gwAAACUKCQSABLSnQEAAIAShUQCQEK6MwAAAFCikEgASEh3BgAAAEoUEgkACenOw29sYv/m+x/OLMwAAMAXMxs+bmUwMrFv3RgAQyUkEgAS0p2H38iOPWGrZxBmAADgC5meDR+3MhjZ/ngcA2C4hOMeAAnpzsNPdwYAGHi6M0APhONejTz90qvvXr/23sVz5y/Ov3997vhL+8Mdnj96+r2F5U+WFheXlxcun/7BNybDHT63755euHg03thw/NxyuH3dLd85c2PhzIvVIywvLy4t3qw0Zps/9d3J1o03577ddv9vv7W0HB4h/Y8zPfnyG/MLjQdcWvzg7JHnG7ccPvLOQvXHxdZgzbs9f2L+k9Ykd/puu+ePzX3Q+tEun3z5UOOW6vEbf7z9+A2HX51fPvda44tDz/3p2RvVoy0vvz/3vZXvRk+9fnl5eenMH6z88cU3FxrLtv5/6z63vXbxxpvfjTc2rKz8z7ylBo5eWDj9nXgjQ093Hn66MwDAwNOdAXogHPfqYua7p9+7+OrXqrjZdOi54xfn32yLoTN/fObm0vzJlRg9+bUT5xZv58tuHXrq8OFYtyufrzvfbqbPn7pW3a1x49LizYW28Y7OLS6v6c49+XG+f+bmwulmIH7mxOXl+RMvvn55+b1TzzS+9fSxucWF0985NndzqTFHa5KnXr+8OH+i+m5zmHXP/tVX55fmjx9ufD35/bnFKqM3Hn/pzPcbj3/ohdPXly8cf+WdpcVPqoer1sALp64tXn61ys2HXnxzYfGdo2sfraX5mO9dX/z5H7duuUt3fvrwV75ya5dooztTY7rz8NOdAQAGnu4M0APhuFcT335rYe7ooWeOnDl39XJ1vvPVy6df/vKRd2+n2+o82fkTT61dqmHym6fOtc7wXWw8QhVJX3xz4dqFi9WJt58sL773xnd/dHb5vVOtBSdfu7j47rEfXVief/ON+ZvLN9483TrfeeU03ob3L85Xtxw/t3x97p2F5inMC2d+8J9auXbx5tkjt576Tt15/x/M3aj6bOPGhdNvNp5rpb1OHj27+O7Z+bbu3OnHuWfmpdcvrJyDfOOdY89U7bJ92uvnzlffXT2xeu2y32prr83xfvLu8vzxlW77vcbXJ77a/HqloR89f3vyxrOsK7/tqb359QtvXLv1+I2vb879XvPrlWVfu9h4gpWROlXg320u1Vj2k7NHZqpb7tSdG891+fSpy4ufLJyeWznf+ZmjrTOpl26cv1jNUD3+5bn3mhto8fLrJ9+Yr7J+tblf+M6plU252NhwrZ+30rYaf/S9t663r+GnfjBXPXi11OXXq0x8ONzh9rI//8/nPrn86m83H7O5Br7dtr1aW6RtX5qbu6o7l0h3Hn66MwDAwNOdAXogHPfq4Rsn37949L7vn7l69nvNHLnitYvXTn2j9fX33l2+0yUXqjNwz73WPCf3a6fmm03wxTcXlt879Vz1OIePXlhafOv/O3Pz+skXGn881Pjj3NHG/5eXFy+++rtfXr3Oxu3ThPcfObtYxdbj55aXV071bdzy/hvPrYmwTW3d+fZ1NpaX5l9/qXmdjcYDHpu72aqrzef9wZpH6PDjVJfjWLxwvHkO8jdef295/vWvrp12ef5k83Iczx//zPOjv/zttxYW3/r+ShFu3thYLavPGH+Wya+dmF9czal3cOi549WZ0U+tqcm3H2TlWaqafPt853hRkabG7c0znRubu/rRWrfcqTsvL144cfjp1ets/HZzvOYjP3fy8nKrOy+vntl98vryu0dvle7vvbN07WS1z1TnaH9w5oXVp761Gp96/XLjMZt9/PCR843t9UevX21sneZDnbi8fP74uju0b4JDR96tbmnc+akTlxtruLGeW/vJPTMvnXy/sUWqHXLuSOOe05MvN4fUncujOw8/3RkAYODpzgA9EI579dBtd24/w/e+Q9WFho9VEfPWSb73vHzmxvtvvPrmwrXT/+qemePnFqprLh+9sLz6sM3uvOZB/vjMzcYkbWV2JWjGVtvenW8306e/f2Zhae5Iszt/pzHz0rnXDlXZtDo1eM0jdOjOL53+YOH0yyt/nDxeZdC1015+dXX9NH7MWytnjeqy0UuL86demFktws3bG/dffcb2SQ69cPzijcXrZ4404+l6My+9en5hsXW95s/uzvcderE6SXl5cXHp2k/OtJ/cvap1mY7q6+dOXW+d7t2hO7f+nWC1Ox9rO5P6t0/NN2Zon+S1i8sXjt+a7aljFxc/Wbp2Ye7ksT+uynXrPm0bvfHFrX8naJg/9dKLp68vf7Iw/86Z149+96nmSgt3uLVsQ3Xq+oXjk/d99fX3Gpu42vrtd557q30Vte6zMgDl0J2Hn+4MADDwdGeAHgjHvZo4fPpy6zob8+9fr66zMX/x9XCdjeYFi9suTNGszL/4RVvmu1N3bp30+rtvXHv/jReb57E2blztpA3N7rwmpx6dq37nXluZXfnummrcdvva7tzqm6dPtrrzPX8wd2P+xOHmibFra2+HH+e1P7pjd26b9nZ3/r2fL934yUutr2955sjctZvXb/2KwuraGp2vs1Fd02N+6cb5Ey+09dl2k988NX9z4dytX/D42dfZaN3e8vKZG23nGrdMHj1b/RLF1US7vHz95O926s6rK6rVnduv4NGaoXN3rm55+vBz//rYyXeuLy7e/meMW0MePX97ndwy+ZXfeeGPTpyeX1h+/42/XneHtT/g0bnFi0efPzH/QePp1vw7QWXNv2HozoXSnYef7gwAMPB0Z4AeCMe9urj77xU8Ord46xfxHXruB2dvVFWx7Tob32xe52HNdTa+/L13lprN96uvzi/cWKhCZ+Oea0vuxfbrbDzz2sXV62ysps/P1Z2fPjpXXWahcWMrOH7/zELjeVtfr32EO/847dfZeOnk1ZXrbLRNu3qdjeYTnfmTr37lhd956tYZ4jPH5m62rkexorqKdOv3Cla/OfBWA12Z5PDp6zfa1/B90/uf/8Zzz1fXiGj6VyffX1ktq1onLDdX1InLy9Vpv9XtKxPOHD+3ejWM3/t5tdonv/I7zx3+6urjHzry7nJ11vnKHxtbpDrje0Pdue06G9XGbaz2zt25ysonWhe+aKyi1fOm2zZ6a520do/mZTT+n9MfrPxQ1a+F/OTsj+Id2jdBpfHTzV+43PpZqu31ztFqI868dPrO19n48jMvfOOZDmWfoaQ7D7/x6ZmxyQOZhRkAAPiCwsetDBofI8MMAEMmJJIaefqlV9+9fu29i9X5zu9fn7t1mu2qya8dO3O1+pV61cUcPrj46jerVjj5zRPnPqh+q9vi6sUiXnxz4dq7Z2/cbN743hsvNrPs5J9W58y2zi9e151v/y64G+fPzFW3rO/O329eUeHOv1fw9vWdV37d363uXLXd5fffOFwtEsv1HX+cletaVD/O0rW3jrZ+qV3btCu/7bDx3eqJGjO0X0H4B2ebv/xwZZjql+zdd/hI4/7NR2v7PYStSaqLLK+5RsSfVs9VNdzW3V5441r7ozV/p2K1olq/xfGDs0dWA/fqhIdeONH8dY4NzdW+0ohbj/bbJ1pX31558MZDHT27fHPuzzfSne9b/b2CN5tX8Gg85vruXD1+8/cKPn9sbmV/WGj/1Yttq/H2Omn92sDbvwlw5VdTxju0Ldv0B3OLzZO1q69nvnvyvTVPd/vRFi6eq36vYOPHWbs4w053BgAAAEoUEsnwWRsxWw793s8XWr8O7rNNfvPMtZvVNaDD7fWwUsnX3Z7OzIkzzc5bW/v/9GL1Gw7X3Q71oTsDAAAAJQqJZPis687Hzy0uLb7/xupVd9c7fOSd6ytn9S5cPrnmyhK10vPu/L2fXz556+zp+qjOKW6e5d3Qdp411JPuDAAAAJQoJBIAEtKdAQAAgBKFRAJAQrozAAAAUKKQSABISHcGAAAAShQSCQAJ6c4AAABAiUIiASAh3RkAAAAoUUgkACSkOwMAAAAlCokEgIR0ZwAAAKBEIZEAkJDuDAAAAJQoJBIAEtKdAQAAgBKFRAJAQrozAAAAUKKQSABIKHbn8amDuU3PhBlILq7zHIZis07Prvu5eu7eXbNxjA7Cgjl4tVJjjf0z7rG9F2aA+gj7ah5hhgEVfqgcpjf61l9n8YfKYaMfS7xBQLuwr+YRZuikL6/WkEgASGhNd24c5cO3M9iy/bH2GeiFTVt3hdXea5vv/1KYYRCN7Xwy/FwZjE0+Gca4s+nZsGAGmx94NI4BtbFl++Nhj83AP8ZQW5u27g67a681PmyEGQZRXwLE6MS+MMYg2rT1ofBz9dqmDX/aHHnwsbBsBmEGqI8+vFq37Q4zdDKyfU9YFoCBpjsXQXfuju4c6M7Ume4M7XTn7ujOXdOdgzAD1IfuDEA2unMRdOfu6M6B7kyd6c7QTnfuju7cNd05CDNAfejOAGSjOxdBd+6O7hzoztSZ7gztdOfu6M5d052DMAPUh+4MQDa6cxF05+7ozoHuTJ3pztBOd+6O7tw13TkIM0B96M4AZKM7F0F37o7uHOjO1JnuDO105+7ozl3TnYMwA9SH7gxANrpzEXTn7ujOge5MnenO0E537o7u3DXdOQgzQH3ozgBkozsXQXfuju4c6M7Ume4M7XTn7ujOXdOdgzAD1IfuDEA2unMRdOfu6M6B7kyd6c7QTnfuju7cNd05CDNAfejOAGSzpjsDAAAAFCIkEgAS0p0BAACAEoVEAkBCujMAAABQopBIAEhIdwYAAABKFBIJAMncN/1fAKniVa/KaFLHAAAAAElFTkSuQmCC"}', 'open', '2025-06-03 16:31:26.056036');


--
-- TOC entry 4048 (class 0 OID 25308)
-- Dependencies: 277
-- Data for Name: message_mentions_enhanced; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4059 (class 0 OID 25646)
-- Dependencies: 288
-- Data for Name: message_mentions_secure; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4029 (class 0 OID 25008)
-- Dependencies: 258
-- Data for Name: message_reactions; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4046 (class 0 OID 25288)
-- Dependencies: 275
-- Data for Name: message_reactions_enhanced; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 3999 (class 0 OID 16479)
-- Dependencies: 228
-- Data for Name: messages; Type: TABLE DATA; Schema: public; Owner: veza
--

INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (1, 3, NULL, 'general', 'testuser: Hello world', '2025-05-14 08:09:26.646215', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (2, 3, NULL, 'general', 'testuser: whouaaa c''est la zazou', '2025-05-14 10:04:01.46018', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (3, 5, NULL, 'afterworks', 'test', '2025-05-16 17:58:48.605015', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (4, 5, NULL, 'general', 'test', '2025-05-16 17:59:28.625264', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (5, 6, NULL, 'general', 'hey', '2025-05-16 18:01:01.85705', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (6, 5, NULL, 'general', 'ca va ?', '2025-05-16 18:01:05.417042', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (7, 6, NULL, 'general', 'oui et toi', '2025-05-16 18:01:10.620099', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (8, 3, NULL, 'general', 'Hello from terminal!', '2025-05-17 12:28:20.87812', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (9, 6, NULL, 'general', 'siouu', '2025-05-17 13:07:18.683595', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (10, 6, NULL, 'general', 'peka', '2025-05-17 13:07:21.773443', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (11, 5, NULL, 'general', 'il y a un probleme ?', '2025-05-17 13:07:37.077497', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (12, 6, NULL, 'general', 'siouu', '2025-05-17 13:07:41.390959', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (13, 6, NULL, 'general', 'test', '2025-05-17 13:22:49.022536', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (14, 5, NULL, 'general', 'avion', '2025-05-17 13:22:52.362462', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (15, 5, NULL, 'general', 'à réaction', '2025-05-17 13:22:56.760171', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (16, 5, NULL, 'general', 'dans la boue', '2025-05-17 13:23:00.717775', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (17, 6, NULL, 'general', 'j''ai essayé', '2025-05-17 13:23:04.048055', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (18, 5, NULL, 'afterworks', 'testing', '2025-05-17 13:34:24.56464', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (19, 6, NULL, 'general', '<script>alert("hacked");*</script>', '2025-05-17 13:51:30.193538', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (20, 6, NULL, 'general', 'tsty', '2025-05-17 14:05:44.174228', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (21, 6, NULL, 'general', 'est', '2025-05-17 14:05:45.400753', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (22, 6, NULL, 'general', 'fx', '2025-05-17 14:05:46.589543', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (23, 5, NULL, 'general', 'testtt', '2025-05-17 14:06:12.653797', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (24, 5, NULL, 'general', 'esf', '2025-05-17 14:06:14.540518', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (25, 6, NULL, 'general', 'ok donc maintenant ca marche', '2025-05-17 14:13:57.097757', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (26, 6, NULL, 'general', 'ya un probleme quand meme', '2025-05-17 14:14:03.587795', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (27, 6, NULL, 'general', 'sqhqsj', '2025-05-17 14:16:56.810294', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (28, 6, NULL, 'general', 'en pétard', '2025-05-17 14:19:38.569998', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (29, 5, NULL, 'general', 'ca riegole pas', '2025-05-17 14:19:50.480501', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (30, 5, NULL, 'general', 'c''est fou', '2025-05-17 14:19:54.539292', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (31, 6, NULL, 'afterworks', 'incoyable', '2025-05-17 14:20:04.378719', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (32, 5, NULL, 'afterworks', 'vraiment', '2025-05-17 14:20:09.634674', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (33, 5, NULL, 'general', 'genre la tout marche', '2025-05-17 14:20:15.205537', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (34, 5, NULL, 'general', 'c''est fou', '2025-05-17 14:20:32.662259', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (35, 6, NULL, 'general', 'test incro', '2025-05-17 14:21:40.680769', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (36, 5, NULL, 'general', 'osqdjdd', '2025-05-17 14:21:44.353604', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (37, 5, NULL, 'general', 'jsdkdd', '2025-05-17 14:21:48.11842', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (38, 5, NULL, 'general', 'fiouu', '2025-05-17 14:32:17.095472', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (39, 5, NULL, 'general', 'ajout', '2025-05-17 14:32:21.962477', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (40, 6, NULL, 'general', 'sjdl', '2025-05-17 14:32:24.519381', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (41, 6, NULL, 'afterworks', 'jdksdkd', '2025-05-17 14:32:27.897236', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (42, 5, NULL, 'general', 'test', '2025-05-17 14:35:30.512052', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (43, 5, NULL, 'general', 'ajout', '2025-05-17 14:35:32.153122', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (44, 6, NULL, 'general', 'final', '2025-05-17 14:35:35.082629', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (45, 6, NULL, 'general', 'test', '2025-05-17 14:38:26.599281', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (46, 5, NULL, 'general', 'avion', '2025-05-17 14:38:30.280868', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (47, 5, NULL, 'general', 'cachou', '2025-05-17 14:38:34.717786', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (48, 5, NULL, 'general', 'test', '2025-05-17 14:38:41.694525', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (49, 6, NULL, 'afterworks', 'callera', '2025-05-17 14:38:46.590603', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (50, 5, NULL, 'afterworks', 'test', '2025-05-17 14:38:52.859089', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (51, 6, NULL, 'general', 'jss', '2025-05-17 14:44:14.183201', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (52, 6, NULL, 'general', 'testing', '2025-05-17 15:05:53.881917', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (53, 5, NULL, 'general', 'seems to work', '2025-05-17 15:06:05.664446', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (54, 5, NULL, 'general', 'we''ll see', '2025-05-17 15:06:09.661665', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (55, 5, NULL, 'general', 'toto is now in afterworks room', '2025-05-17 15:06:20.931807', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (56, 6, NULL, 'afterworks', 'he doesn''t see a zoukou msg from egneral room', '2025-05-17 15:06:33.487061', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (57, 6, NULL, 'afterworks', 'so bug fixed', '2025-05-17 15:06:35.895411', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (58, 6, NULL, 'general', 'fou', '2025-05-17 15:10:18.93665', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (59, 6, NULL, 'afterworks', 'incr', '2025-05-17 15:10:31.571454', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (60, 5, NULL, 'general', 'fifi', '2025-05-17 15:20:40.624171', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (61, 6, 5, NULL, 'test', '2025-05-17 16:02:19.936134', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (62, 5, 6, NULL, 'test', '2025-05-17 16:02:30.820598', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (63, 6, 5, NULL, 'incroybalke', '2025-05-17 16:02:34.624062', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (64, 5, 6, NULL, 'ca fonctionne on dirait', '2025-05-17 16:02:41.124823', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (65, 6, 5, NULL, 'oui apparememnt', '2025-05-17 16:02:46.639404', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (66, 5, 6, NULL, 'ok on voit si ca arche', '2025-05-17 16:07:22.176381', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (67, 6, 5, NULL, 'ca a pas l''air', '2025-05-17 16:07:34.065075', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (68, 5, 6, NULL, 'il y a que l''autre', '2025-05-17 16:07:39.463208', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (69, 6, 5, NULL, 'test', '2025-05-17 16:14:16.014101', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (70, 5, 6, NULL, 'avion', '2025-05-17 16:14:23.268292', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (71, 6, 5, NULL, 'à réaction ?', '2025-05-17 16:14:28.024603', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (72, 5, 6, NULL, 'ou à ballons ?', '2025-05-17 16:14:32.725111', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (73, 6, 5, NULL, 'à émotions ?', '2025-05-17 16:14:38.250447', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (74, 7, NULL, 'general', 'coucou', '2025-05-18 13:01:57.684899', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (75, 7, NULL, 'general', 'coucou', '2025-05-18 13:02:09.652751', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (76, 10, NULL, 'general', 'coucou', '2025-05-18 13:02:24.060334', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (77, 7, 10, NULL, 'siouu', '2025-05-18 13:39:25.404866', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (78, 10, 7, NULL, 'ca va', '2025-05-18 13:39:28.713857', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (79, 7, 10, NULL, 'oui et toi', '2025-05-18 13:39:32.839204', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (80, 10, 7, NULL, 'ddzzz', '2025-05-18 15:04:13.479396', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (81, 10, 7, NULL, 'test', '2025-05-18 17:15:35.660566', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (82, 10, 7, NULL, 'test', '2025-05-18 17:18:39.995458', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (83, 10, 7, NULL, 'sympa', '2025-05-18 17:22:07.281441', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (84, 5, NULL, 'general', 'sifiliiii', '2025-05-30 14:28:15.497466', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (85, 5, NULL, 'afterworks', 'dodo', '2025-05-30 14:28:21.313166', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (86, 5, NULL, 'afterworks', 'sifili', '2025-05-30 14:28:30.906011', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (87, 5, NULL, 'general', 'sifili', '2025-05-30 14:28:38.138026', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (88, 5, NULL, 'general', 'sifili', '2025-05-30 14:28:51.67819', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (89, 5, 10, NULL, 'test', '2025-05-30 14:57:39.556702', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (90, 5, 10, NULL, 'test avec marko', '2025-05-30 15:01:53.119959', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (91, 5, 10, NULL, 'markoo*', '2025-05-30 15:02:02.627174', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (92, 5, 8, NULL, 'test avec marko', '2025-05-30 15:02:10.107562', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (93, 5, 7, NULL, 'test avec biddie', '2025-05-30 15:02:16.086658', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (94, 5, 6, NULL, 'test avec toto', '2025-05-30 15:02:22.319899', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (95, 5, 3, NULL, 'test avec testuser', '2025-05-30 15:02:28.963108', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (96, 11, 5, NULL, 'ca va ou quoi', '2025-05-30 15:12:31.868576', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (97, 5, 11, NULL, 'oui trkl et toi', '2025-05-30 15:12:43.243662', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (98, 11, 5, NULL, 'bah je vois pas nos ancieen messages donc non', '2025-05-30 15:12:54.490768', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (99, 5, 6, NULL, 'jshdsqdq', '2025-05-30 15:31:37.933694', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (100, 5, 6, NULL, 'qsdjqskd', '2025-05-30 15:31:38.695783', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (101, 5, 6, NULL, 'qsdjqsndnqs', '2025-05-30 15:31:39.432868', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (102, 5, 6, NULL, 'qs nddn', '2025-05-30 15:31:40.323567', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (103, 5, 6, NULL, 'sqd,nd*sqdn', '2025-05-30 15:31:41.866816', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (104, 5, 6, NULL, 'qsndlqsd', '2025-05-30 15:31:42.921938', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (105, 5, 6, NULL, ',sqds', '2025-05-30 15:31:43.697512', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (106, 5, 6, NULL, ',sqds', '2025-05-30 15:31:44.533865', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (107, 5, 6, NULL, ',sqd', '2025-05-30 15:31:45.329471', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (108, 5, 6, NULL, 'sqd', '2025-05-30 15:31:46.198819', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (109, 5, 6, NULL, 'qs,d', '2025-05-30 15:31:46.898809', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (110, 5, 6, NULL, 'qsd,sq', '2025-05-30 15:31:47.617931', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (111, 5, 6, NULL, '*d,dqs', '2025-05-30 15:31:48.357704', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (112, 5, 6, NULL, 'd,qs', '2025-05-30 15:31:49.040103', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (113, 5, 6, NULL, 'sdq,dsq', '2025-05-30 15:31:49.742102', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (114, 12, NULL, 'afterworks', 'castel red', '2025-05-31 15:46:00.919832', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (115, 12, NULL, 'afterworks', 'nikola', '2025-05-31 15:46:11.339157', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (116, 12, NULL, 'afterworks', 'oui oui', '2025-06-03 12:41:07.267214', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (117, 12, NULL, 'afterworks', 'test', '2025-06-03 12:44:03.142528', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (118, 12, NULL, 'general', 'test', '2025-06-03 12:44:08.136559', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (119, 12, NULL, 'general', 'fouuu', '2025-06-03 12:44:11.166248', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (120, 5, 7, NULL, 'test', '2025-06-03 13:03:35.018931', 'text', NULL, false, NULL, NULL, false, 0, 'sent');
INSERT INTO "public"."messages" ("id", "from_user", "to_user", "room", "content", "created_at", "message_type", "reply_to_id", "is_edited", "edited_at", "metadata", "is_pinned", "thread_count", "status") VALUES (121, 5, NULL, 'afterworks', 'zoo', '2025-06-03 13:19:04.487317', 'text', NULL, false, NULL, NULL, false, 0, 'sent');


--
-- TOC entry 4044 (class 0 OID 25249)
-- Dependencies: 273
-- Data for Name: messages_enhanced; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4021 (class 0 OID 24885)
-- Dependencies: 250
-- Data for Name: migrations; Type: TABLE DATA; Schema: public; Owner: veza
--

INSERT INTO "public"."migrations" ("id", "filename", "applied_at") VALUES (1, '001_users.sql', '2025-06-04 16:58:28.04282');
INSERT INTO "public"."migrations" ("id", "filename", "applied_at") VALUES (2, 'files.sql', '2025-06-04 18:22:46.819163');
INSERT INTO "public"."migrations" ("id", "filename", "applied_at") VALUES (3, 'internal_ressources.sql', '2025-06-04 18:22:46.822494');


--
-- TOC entry 4035 (class 0 OID 25078)
-- Dependencies: 264
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4011 (class 0 OID 24729)
-- Dependencies: 240
-- Data for Name: offers; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- TOC entry 4019 (class 0 OID 24841)
-- Dependencies: 248
-- Data for Name: product_documents; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4013 (class 0 OID 24771)
-- Dependencies: 242
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."products" ("id", "name", "category_id", "brand", "model", "description", "price", "warranty_months", "warranty_conditions", "manufacturer_website", "specifications", "status", "created_at", "updated_at") VALUES (1, 'Microphone USB', 1, '', '', '', NULL, 24, '', '', '', 'active', '2025-06-04 10:51:30.914438', '2025-06-04 10:51:30.916989');
INSERT INTO "public"."products" ("id", "name", "category_id", "brand", "model", "description", "price", "warranty_months", "warranty_conditions", "manufacturer_website", "specifications", "status", "created_at", "updated_at") VALUES (2, 'Interface audio', 2, '', '', '', NULL, 24, '', '', '', 'active', '2025-06-04 10:51:30.914438', '2025-06-04 10:51:30.918816');
INSERT INTO "public"."products" ("id", "name", "category_id", "brand", "model", "description", "price", "warranty_months", "warranty_conditions", "manufacturer_website", "specifications", "status", "created_at", "updated_at") VALUES (3, 'Casque monitoring', 3, '', '', '', NULL, 12, '', '', '', 'active', '2025-06-04 10:51:30.914438', '2025-06-04 10:51:30.919537');
INSERT INTO "public"."products" ("id", "name", "category_id", "brand", "model", "description", "price", "warranty_months", "warranty_conditions", "manufacturer_website", "specifications", "status", "created_at", "updated_at") VALUES (4, 'Enceintes de studio', 4, '', '', '', NULL, 24, '', '', '', 'active', '2025-06-04 10:51:30.914438', '2025-06-04 10:51:30.920173');
INSERT INTO "public"."products" ("id", "name", "category_id", "brand", "model", "description", "price", "warranty_months", "warranty_conditions", "manufacturer_website", "specifications", "status", "created_at", "updated_at") VALUES (5, 'Contrôleur MIDI', 5, '', '', '', NULL, 12, '', '', '', 'active', '2025-06-04 10:51:30.914438', '2025-06-04 10:51:30.920727');
INSERT INTO "public"."products" ("id", "name", "category_id", "brand", "model", "description", "price", "warranty_months", "warranty_conditions", "manufacturer_website", "specifications", "status", "created_at", "updated_at") VALUES (6, 'Table de mixage', 6, '', '', '', NULL, 24, '', '', '', 'active', '2025-06-04 10:51:30.914438', '2025-06-04 10:51:30.921408');
INSERT INTO "public"."products" ("id", "name", "category_id", "brand", "model", "description", "price", "warranty_months", "warranty_conditions", "manufacturer_website", "specifications", "status", "created_at", "updated_at") VALUES (7, 'Préampli micro', 7, '', '', '', NULL, 24, '', '', '', 'active', '2025-06-04 10:51:30.914438', '2025-06-04 10:51:30.92195');
INSERT INTO "public"."products" ("id", "name", "category_id", "brand", "model", "description", "price", "warranty_months", "warranty_conditions", "manufacturer_website", "specifications", "status", "created_at", "updated_at") VALUES (8, 'Compresseur', 7, '', '', '', NULL, 24, '', '', '', 'active', '2025-06-04 10:51:30.914438', '2025-06-04 10:51:30.92195');
INSERT INTO "public"."products" ("id", "name", "category_id", "brand", "model", "description", "price", "warranty_months", "warranty_conditions", "manufacturer_website", "specifications", "status", "created_at", "updated_at") VALUES (9, 'Égaliseur', 7, '', '', '', NULL, 24, '', '', '', 'active', '2025-06-04 10:51:30.914438', '2025-06-04 10:51:30.92195');
INSERT INTO "public"."products" ("id", "name", "category_id", "brand", "model", "description", "price", "warranty_months", "warranty_conditions", "manufacturer_website", "specifications", "status", "created_at", "updated_at") VALUES (10, 'Câble XLR', 8, '', '', '', NULL, 6, '', '', '', 'active', '2025-06-04 10:51:30.914438', '2025-06-04 10:51:30.925163');


--
-- TOC entry 4025 (class 0 OID 24956)
-- Dependencies: 254
-- Data for Name: refresh_tokens; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."refresh_tokens" ("id", "user_id", "token", "expires_at", "created_at") VALUES (1, 6, 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjo2LCJ1c2VybmFtZSI6InRlc3RlciIsInJvbGUiOiJ1c2VyIiwiZXhwIjoxNzUwMTgyMzAxLCJpYXQiOjE3NDk1Nzc1MDF9.5itXtCtghbj5z4eallR2oe-pWcG1D30TFKkGQZpcv7k', '2025-06-17 17:45:01.919772', '2025-06-10 17:45:01.919772');
INSERT INTO "public"."refresh_tokens" ("id", "user_id", "token", "expires_at", "created_at") VALUES (5, 7, 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjo3LCJ1c2VybmFtZSI6ImZpbG91Iiwicm9sZSI6InVzZXIiLCJleHAiOjE3NTAyMzUxOTMsImlhdCI6MTc0OTYzMDM5M30.3luCJtwfF45mkm1Xu0TZQZFHZfOlOY1DRTNa_c1TlXE', '2025-06-18 08:26:33.976361', '2025-06-11 08:26:33.976361');
INSERT INTO "public"."refresh_tokens" ("id", "user_id", "token", "expires_at", "created_at") VALUES (17, 9, 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjo5LCJ1c2VybmFtZSI6ImF2aW9uIiwicm9sZSI6InVzZXIiLCJleHAiOjE3NTAyMzU5NTgsImlhdCI6MTc0OTYzMTE1OH0.ZuaPisUgLVpRAhHKyhKYmbYpC-_7UIgyrCgvGQdKUpw', '2025-06-18 08:39:18.979907', '2025-06-11 08:39:18.979907');
INSERT INTO "public"."refresh_tokens" ("id", "user_id", "token", "expires_at", "created_at") VALUES (20, 10, 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoxMCwidXNlcm5hbWUiOiJuaWtvIiwicm9sZSI6InVzZXIiLCJleHAiOjE3NTAyNjgwNDgsImlhdCI6MTc0OTY2MzI0OH0.x9qzymi4Q12LjojOB28XK_M-vUN_RkWchOZbQ8muCYg', '2025-06-18 17:34:08.661378', '2025-06-11 17:34:08.661378');
INSERT INTO "public"."refresh_tokens" ("id", "user_id", "token", "expires_at", "created_at") VALUES (16, 8, 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjo4LCJ1c2VybmFtZSI6ImtvdWJvdSIsInJvbGUiOiJ1c2VyIiwiZXhwIjoxNzUwMzU1NzgzLCJpYXQiOjE3NDk3NTA5ODN9.5uRfUUQd5LDi7-n45yvYgwyTGMeEtwb8pSmpmW8PwMI', '2025-06-19 17:56:23.948688', '2025-06-12 17:56:23.948688');
INSERT INTO "public"."refresh_tokens" ("id", "user_id", "token", "expires_at", "created_at") VALUES (22, 11, 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoxMSwidXNlcm5hbWUiOiJ0ZXN0Iiwicm9sZSI6InVzZXIiLCJleHAiOjE3NTAzNTYyNTUsImlhdCI6MTc0OTc1MTQ1NX0.8vwhM9C9ODKxmqPVPFh3ES_KBxk5N57MtKLrsb9ZX40', '2025-06-19 18:04:15.094627', '2025-06-12 18:04:15.094627');
INSERT INTO "public"."refresh_tokens" ("id", "user_id", "token", "expires_at", "created_at") VALUES (43, 15, 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoxNSwidXNlcm5hbWUiOiJ0ZXN0Y2hhdCIsInJvbGUiOiJ1c2VyIiwiZXhwIjoxNzUwNjY2MzQ5LCJpYXQiOjE3NTAwNjE1NDl9.bbHwXplbwVeBMh4loJKc4Py7xqP_LgaIAsyS8xMaSew', '2025-06-23 08:12:29.181905', '2025-06-16 08:12:29.181905');
INSERT INTO "public"."refresh_tokens" ("id", "user_id", "token", "expires_at", "created_at") VALUES (54, 14, 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoxNCwidXNlcm5hbWUiOiJsb3Vsb3UiLCJyb2xlIjoidXNlciIsImV4cCI6MTc1MDg3NDY2MywiaWF0IjoxNzUwMjY5ODYzfQ.fPcYobQIeYJDVtH7RSt0ETRXeFAR5kXR6k8Pnpb2Jxo', '2025-06-25 18:04:23.522064', '2025-06-18 18:04:23.522064');


--
-- TOC entry 4006 (class 0 OID 16560)
-- Dependencies: 235
-- Data for Name: ressource_tags; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- TOC entry 4033 (class 0 OID 25054)
-- Dependencies: 262
-- Data for Name: room_members; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4049 (class 0 OID 25328)
-- Dependencies: 278
-- Data for Name: room_members_enhanced; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 3997 (class 0 OID 16466)
-- Dependencies: 226
-- Data for Name: rooms; Type: TABLE DATA; Schema: public; Owner: veza
--

INSERT INTO "public"."rooms" ("id", "name", "is_private", "created_at", "creator_id", "max_members", "description") VALUES (1, 'general', false, '2025-05-14 08:05:03.902599', NULL, 1000, NULL);
INSERT INTO "public"."rooms" ("id", "name", "is_private", "created_at", "creator_id", "max_members", "description") VALUES (2, 'afterworks', false, '2025-05-14 08:06:14.174808', NULL, 1000, NULL);


--
-- TOC entry 4042 (class 0 OID 25229)
-- Dependencies: 271
-- Data for Name: rooms_enhanced; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4027 (class 0 OID 24985)
-- Dependencies: 256
-- Data for Name: sanctions; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4054 (class 0 OID 25388)
-- Dependencies: 283
-- Data for Name: security_events_enhanced; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4057 (class 0 OID 25623)
-- Dependencies: 286
-- Data for Name: security_events_secure; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4007 (class 0 OID 16575)
-- Dependencies: 236
-- Data for Name: shared_ressource_tags; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- TOC entry 4003 (class 0 OID 16532)
-- Dependencies: 232
-- Data for Name: shared_ressources; Type: TABLE DATA; Schema: public; Owner: veza
--

INSERT INTO "public"."shared_ressources" ("id", "title", "filename", "url", "type", "tags", "uploader_id", "is_public", "uploaded_at", "download_count", "description") VALUES (1, 'tuto de debutant', 'secu_indus.pdf', '/shared/secu_indus.pdf', 'manuel d''apprentissage', '{}', 5, true, '2025-05-30 10:50:00.563246', 0, NULL);
INSERT INTO "public"."shared_ressources" ("id", "title", "filename", "url", "type", "tags", "uploader_id", "is_public", "uploaded_at", "download_count", "description") VALUES (2, 'test2', '2A361-68306A00-C67-4D36D880', '/shared/2A361-68306A00-C67-4D36D880', 'super test photo', '{}', 5, true, '2025-05-30 10:52:31.422027', 0, NULL);
INSERT INTO "public"."shared_ressources" ("id", "title", "filename", "url", "type", "tags", "uploader_id", "is_public", "uploaded_at", "download_count", "description") VALUES (3, 'rori', 'login.png', '/shared_ressources/login.png', 'fifi', '{}', 5, true, '2025-05-30 10:57:36.869579', 0, NULL);
INSERT INTO "public"."shared_ressources" ("id", "title", "filename", "url", "type", "tags", "uploader_id", "is_public", "uploaded_at", "download_count", "description") VALUES (4, 'test', 'ciso_diff.png', '/shared_ressources/ciso_diff.png', 'simple gtest', '{}', 5, true, '2025-05-30 13:37:26.457538', 0, NULL);
INSERT INTO "public"."shared_ressources" ("id", "title", "filename", "url", "type", "tags", "uploader_id", "is_public", "uploaded_at", "download_count", "description") VALUES (6, 'test sample plouf', 'plouf.mp3', '/shared_ressources/plouf.mp3', 'sample', '{hiphop}', 5, true, '2025-05-30 14:09:03.326992', 2, NULL);
INSERT INTO "public"."shared_ressources" ("id", "title", "filename", "url", "type", "tags", "uploader_id", "is_public", "uploaded_at", "download_count", "description") VALUES (5, 'test PDF', 'Logic_exercise.pdf', '/shared_ressources/Logic_exercise.pdf', 'simple pdf file', '{}', 5, true, '2025-05-30 13:58:28.021846', 1, NULL);
INSERT INTO "public"."shared_ressources" ("id", "title", "filename", "url", "type", "tags", "uploader_id", "is_public", "uploaded_at", "download_count", "description") VALUES (7, 'test', 'sample.mp3', '/shared_ressources/sample.mp3', 'sample', '{ambient}', 5, true, '2025-05-30 14:38:02.738878', 1, NULL);
INSERT INTO "public"."shared_ressources" ("id", "title", "filename", "url", "type", "tags", "uploader_id", "is_public", "uploaded_at", "download_count", "description") VALUES (8, 'Incroybale', 'sample(1).mp3', '/shared_ressources/sample(1).mp3', 'sample', '{lofi,hiphop}', 5, true, '2025-05-30 15:34:36.495663', 0, 'Ce sample est vraiment treanscandant !!!!');


--
-- TOC entry 4005 (class 0 OID 16550)
-- Dependencies: 234
-- Data for Name: tags; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."tags" ("id", "name") VALUES (1, 'hiphop');
INSERT INTO "public"."tags" ("id", "name") VALUES (2, 'ambient');
INSERT INTO "public"."tags" ("id", "name") VALUES (3, 'techno');
INSERT INTO "public"."tags" ("id", "name") VALUES (4, 'trap');
INSERT INTO "public"."tags" ("id", "name") VALUES (5, 'lofi');
INSERT INTO "public"."tags" ("id", "name") VALUES (6, 'synth');


--
-- TOC entry 4001 (class 0 OID 16499)
-- Dependencies: 230
-- Data for Name: tracks; Type: TABLE DATA; Schema: public; Owner: veza
--

INSERT INTO "public"."tracks" ("id", "title", "filename", "artist", "duration_seconds", "tags", "is_public", "uploader_id", "created_at") VALUES (4, 'test', 'plouf.mp3', 'fifi', 0, '{Volvo,BMW,Ford,Mazda}', true, 6, '2025-05-23 16:56:50.758795');
INSERT INTO "public"."tracks" ("id", "title", "filename", "artist", "duration_seconds", "tags", "is_public", "uploader_id", "created_at") VALUES (7, 'piji', 'plouf.mp3', 'kiri', 0, '{fou,kiri,piji}', true, 5, '2025-05-23 18:33:56.60302');
INSERT INTO "public"."tracks" ("id", "title", "filename", "artist", "duration_seconds", "tags", "is_public", "uploader_id", "created_at") VALUES (8, 'test', 'plouf.mp3', 'tags', 0, '{test,tags}', true, 5, '2025-05-23 18:34:37.668528');
INSERT INTO "public"."tracks" ("id", "title", "filename", "artist", "duration_seconds", "tags", "is_public", "uploader_id", "created_at") VALUES (9, 'gdy', 'plouf.mp3', 'dqshdjs', 0, '{dghd,dhjdkd,dhjdkd}', true, 5, '2025-05-23 18:40:34.383879');
INSERT INTO "public"."tracks" ("id", "title", "filename", "artist", "duration_seconds", "tags", "is_public", "uploader_id", "created_at") VALUES (10, 'pina', 'plouf.mp3', 'anip', 0, '{anipa,pina,colada}', true, 5, '2025-05-23 18:45:00.084096');
INSERT INTO "public"."tracks" ("id", "title", "filename", "artist", "duration_seconds", "tags", "is_public", "uploader_id", "created_at") VALUES (2, 'test', 'plouf.mp3', 'okin', 0, '{toto,tata}', true, 6, '2025-05-23 16:31:56.314939');
INSERT INTO "public"."tracks" ("id", "title", "filename", "artist", "duration_seconds", "tags", "is_public", "uploader_id", "created_at") VALUES (3, 'foo', 'plouf.mp3', 'ars', 0, '{toto,tata}', true, 6, '2025-05-23 16:34:35.002136');
INSERT INTO "public"."tracks" ("id", "title", "filename", "artist", "duration_seconds", "tags", "is_public", "uploader_id", "created_at") VALUES (5, 'enpetard', 'plouf.mp3', 'fifo', 0, '{toto,tata}', true, 6, '2025-05-23 16:58:23.42973');
INSERT INTO "public"."tracks" ("id", "title", "filename", "artist", "duration_seconds", "tags", "is_public", "uploader_id", "created_at") VALUES (6, 'mom', 'plouf.mp3', 'biddie', 0, '{toto,tata}', true, 6, '2025-05-23 18:00:27.500213');
INSERT INTO "public"."tracks" ("id", "title", "filename", "artist", "duration_seconds", "tags", "is_public", "uploader_id", "created_at") VALUES (11, 'puk', 'plouf.mp3', 'plouf', 0, '{byk,vuk,chat}', true, 5, '2025-05-23 19:11:29.767932');
INSERT INTO "public"."tracks" ("id", "title", "filename", "artist", "duration_seconds", "tags", "is_public", "uploader_id", "created_at") VALUES (12, 'sample1', 'sample.mp3', 'testgit', 0, '{git,test,sample1}', true, 5, '2025-05-23 19:26:34.776908');
INSERT INTO "public"."tracks" ("id", "title", "filename", "artist", "duration_seconds", "tags", "is_public", "uploader_id", "created_at") VALUES (13, 'sample2', 'sample2.mp3', 'testgit', 0, '{git,test,sample2}', true, 5, '2025-05-23 19:27:07.952759');
INSERT INTO "public"."tracks" ("id", "title", "filename", "artist", "duration_seconds", "tags", "is_public", "uploader_id", "created_at") VALUES (14, 'kata', 'sample2.mp3', 'superkat', 0, '{theo,réunion,bringelle}', true, 5, '2025-05-23 23:22:28.657177');
INSERT INTO "public"."tracks" ("id", "title", "filename", "artist", "duration_seconds", "tags", "is_public", "uploader_id", "created_at") VALUES (15, 'Sin,dbad', 'sample(1).mp3', 'badou', 0, '{castel,red}', true, 12, '2025-05-31 15:46:50.696558');


--
-- TOC entry 4031 (class 0 OID 25029)
-- Dependencies: 260
-- Data for Name: user_blocks; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4051 (class 0 OID 25347)
-- Dependencies: 280
-- Data for Name: user_blocks_enhanced; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4061 (class 0 OID 25667)
-- Dependencies: 290
-- Data for Name: user_blocks_secure; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4015 (class 0 OID 24787)
-- Dependencies: 244
-- Data for Name: user_products; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."user_products" ("id", "user_id", "product_id", "version", "purchase_date", "warranty_expires", "created_at") VALUES (1, 3, 1, 'v1.0', '2025-05-13', '2030-05-13', '2025-06-04 10:21:07.76846');
INSERT INTO "public"."user_products" ("id", "user_id", "product_id", "version", "purchase_date", "warranty_expires", "created_at") VALUES (2, 5, 1, '1.2', '2025-05-14', '2025-05-29', '2025-06-04 10:21:07.76846');
INSERT INTO "public"."user_products" ("id", "user_id", "product_id", "version", "purchase_date", "warranty_expires", "created_at") VALUES (3, 5, 1, '1.1', '2024-11-09', '2222-02-28', '2025-06-04 10:21:07.76846');
INSERT INTO "public"."user_products" ("id", "user_id", "product_id", "version", "purchase_date", "warranty_expires", "created_at") VALUES (4, 5, 1, '24', '2025-05-06', '2025-05-27', '2025-06-04 10:21:07.76846');
INSERT INTO "public"."user_products" ("id", "user_id", "product_id", "version", "purchase_date", "warranty_expires", "created_at") VALUES (5, 5, 1, '1.0', '2025-05-15', '2026-05-15', '2025-06-04 10:21:07.76846');
INSERT INTO "public"."user_products" ("id", "user_id", "product_id", "version", "purchase_date", "warranty_expires", "created_at") VALUES (6, 6, 1, '12', '2025-05-06', '2025-05-27', '2025-06-04 10:21:07.76846');
INSERT INTO "public"."user_products" ("id", "user_id", "product_id", "version", "purchase_date", "warranty_expires", "created_at") VALUES (7, 6, 1, '34', '2025-04-30', '2025-06-06', '2025-06-04 10:21:07.76846');
INSERT INTO "public"."user_products" ("id", "user_id", "product_id", "version", "purchase_date", "warranty_expires", "created_at") VALUES (8, 10, 1, '103', '2023-03-23', '2025-03-23', '2025-06-04 10:21:07.76846');
INSERT INTO "public"."user_products" ("id", "user_id", "product_id", "version", "purchase_date", "warranty_expires", "created_at") VALUES (9, 12, 1, '12', '2025-05-14', '2025-05-08', '2025-06-04 10:21:07.76846');


--
-- TOC entry 4037 (class 0 OID 25097)
-- Dependencies: 266
-- Data for Name: user_sessions; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4052 (class 0 OID 25369)
-- Dependencies: 281
-- Data for Name: user_sessions_enhanced; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4055 (class 0 OID 25600)
-- Dependencies: 284
-- Data for Name: user_sessions_secure; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4023 (class 0 OID 24924)
-- Dependencies: 252
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: veza
--

INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (1, 'test_user', 'test@free.fr', '$2a$10$zqSerwfpsErKDKB/s3rnYuDBCs9AkwntWFUTrTBV3xDhCLDCcYWQq', '', '', '', '', 'user', true, false, NULL, '2025-06-06 15:53:31.838708', '2025-06-06 15:53:31.838708', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);
INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (2, 'testuser', 'test@example.com', '$2a$10$1CBH45rwl3OXdNHH9Sgt9O.MmHHvxjpd5uZIm9FT5lccRHB1HlRQC', '', '', '', '', 'user', true, false, NULL, '2025-06-06 16:02:08.821544', '2025-06-06 16:02:08.821544', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);
INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (3, 'newuser', 'new@example.com', '$2a$10$TcUbD6arex3jgPUeEZ1RPOYdvNdIfr/vpwtEedlhP2iPMtkp8jHw6', '', '', '', '', 'user', true, false, NULL, '2025-06-06 16:16:11.234989', '2025-06-06 16:16:11.234989', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);
INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (4, 'newuser2', 'new2@example.com', '$2a$10$gPFVka9twToCAb3CMGaCPOXLHjzzMqaocun77d2iHP4o0N/zkqbTS', '', '', '', '', 'user', true, false, NULL, '2025-06-06 16:31:54.479521', '2025-06-06 16:31:54.479521', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);
INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (5, 'harry', 'harry@example.com', '$2a$10$6WHrKaqVzsiD5A.yZAMjFOtaCPJ1MIuI.d25FjxRdsJFTOM28YwJC', '', '', '', '', 'user', true, false, NULL, '2025-06-06 17:33:55.844063', '2025-06-06 17:33:55.844063', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);
INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (6, 'tester', 'tester@free.fr', '$2a$10$Tukex8wH0iLa40Bh.qld6eEf43GWPY.xC0WuKUedafkEtUmlzxmgy', '', '', '', '', 'user', true, false, NULL, '2025-06-09 15:05:26.840141', '2025-06-09 15:05:26.840141', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);
INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (7, 'filou', 'filou@example.com', '$2a$10$sy/ZsrHNATYbraeUaeGjq.m3sDwomn1SlClVgrO3meCrJ53Ng6g.a', '', '', '', '', 'user', true, false, NULL, '2025-06-09 16:47:26.914866', '2025-06-09 16:47:26.914866', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);
INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (8, 'koubou', 'koubou@example.com', '$2a$10$lu3WGzaAK73pUUM1cyAGWeYFA2kIpx/5rBtyquXgpnEL4I6clbTee', '', '', '', '', 'user', true, false, NULL, '2025-06-11 08:28:13.931282', '2025-06-11 08:28:13.931282', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);
INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (9, 'avion', 'avion@free.fr', '$2a$10$DaPn4lEhppsvvxM5xi2LauDP3YcfaE6cMeMR9cfo4bx9nLV7fdKcW', '', '', '', '', 'user', true, false, NULL, '2025-06-11 08:35:59.612549', '2025-06-11 08:35:59.612549', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);
INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (10, 'niko', 'niko@free.fr', '$2a$10$8iVau2eAxznWlm0XlSvYVei3Z8lg3P0lK6dYi9ryRXzX8b2TSEpvC', '', '', '', '', 'user', true, false, NULL, '2025-06-11 17:33:58.607696', '2025-06-11 17:33:58.607696', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);
INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (11, 'test', 'test@a.fr', '$2a$10$PNlt1NxLwq6W3ukIbSZ2ve1gkpuFonLli5oZsf55XF2TAa/Z0k/8K', '', '', '', '', 'user', true, false, NULL, '2025-06-12 17:56:36.371586', '2025-06-12 17:56:36.371586', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);
INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (12, 'shelby', 'shelby@free.fr', '$2a$10$N6z8ZdHvUTqiT6Ugq2iiYuECnm6Mb2ebiBcZgMM30VJMUoJBMZ07G', '', '', '', '', 'user', true, false, NULL, '2025-06-13 20:44:47.878159', '2025-06-13 20:44:47.878159', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);
INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (13, 'panda', 'panda@free.fr', '$2a$10$tkDptfrSpJ.PgUjfHcKaXOTypxeUsLG9B7gzlHCgHKZ/LB2WRfory', '', '', '', '', 'user', true, false, NULL, '2025-06-13 20:46:47.469178', '2025-06-13 20:46:47.469178', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);
INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (14, 'loulou', 'loulou@free.fr', '$2a$10$1/Y0oSNjbMhPdE.lgrBD9uLC91lgE8tQfomEvUS2sMNZtAtsIvCO.', '', '', '', '', 'user', true, false, NULL, '2025-06-13 21:03:54.702786', '2025-06-13 21:03:54.702786', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);
INSERT INTO "public"."users" ("id", "username", "email", "password_hash", "first_name", "last_name", "avatar", "bio", "role", "is_active", "is_verified", "last_login_at", "created_at", "updated_at", "status", "last_seen", "reputation_score", "is_banned", "is_muted") VALUES (15, 'testchat', 'testchat@example.com', '$2a$10$rrc2jDHBcGJT7V/3OXMH.elkEXuDmK1IGsy9TbexKQT..VK3eso3a', '', '', '', '', 'user', true, false, NULL, '2025-06-16 01:11:11.817287', '2025-06-16 01:11:11.817287', 'offline', '2025-06-18 21:53:32.702861+00', 100, false, false);


--
-- TOC entry 3991 (class 0 OID 16391)
-- Dependencies: 220
-- Data for Name: users_backup; Type: TABLE DATA; Schema: public; Owner: veza
--

INSERT INTO "public"."users_backup" ("id", "username", "email", "password_hash", "created_at") VALUES (3, 'testuser', 'test@test.com', '$2a$10$1JxQq7ixxMt35md1dMeDaugFOkItpvv38tXNkUAk/wZnHWbp8FhF.', '2025-05-13 09:15:43.423562');
INSERT INTO "public"."users_backup" ("id", "username", "email", "password_hash", "created_at") VALUES (5, 'zoukou', 'test@free.fr', '$2a$10$GNE2UZVOow8wuSy64/XOIOaNMy5LRCtuc9PgVov3M4V4FUrTqhYrK', '2025-05-16 13:02:44.503381');
INSERT INTO "public"."users_backup" ("id", "username", "email", "password_hash", "created_at") VALUES (6, 'toto', 'toto@free.fr', '$2a$10$3LHebgw7dFqU8XjOFvu26u.KrgFVQ.5cPQtJnYrXNi0E9NIOw.Jwm', '2025-05-16 18:00:34.344034');
INSERT INTO "public"."users_backup" ("id", "username", "email", "password_hash", "created_at") VALUES (7, 'biddie', 'biddie@free.fr', '$2a$10$nw8.duzL2ODfkgmw3Nvl3.9BI1/6n0pD7z9Wi24tfRaMroHX6Mzh.', '2025-05-18 12:53:41.217726');
INSERT INTO "public"."users_backup" ("id", "username", "email", "password_hash", "created_at") VALUES (8, 'marko', 'milo@free.fr', '$2a$10$NgoHPvldNzvUOBNB3FcKUe.fSzKMXgNOo0omSrA2Sn0wmgDjydE1C', '2025-05-18 12:53:45.671077');
INSERT INTO "public"."users_backup" ("id", "username", "email", "password_hash", "created_at") VALUES (10, 'markoo', 'marko@free.fr', '$2a$10$65lxRhgEAEpUexqFHQAwYeuS5vOKiEfj6ZkzlRJ9UA.26UisSlF3i', '2025-05-18 12:56:45.522691');
INSERT INTO "public"."users_backup" ("id", "username", "email", "password_hash", "created_at") VALUES (11, 'okinrev', 'okinrev@free.fr', '$2a$10$.TLm.iqPZGzK9HU0WM3Psee/s3gu2ww9JYfo3zdbJju86iUriIXAO', '2025-05-30 15:10:51.701245');
INSERT INTO "public"."users_backup" ("id", "username", "email", "password_hash", "created_at") VALUES (12, 'bedou', 'badou@free.fr', '$2a$10$8F2hr0zTqc1RgtG7XfnD3uwB/OBj6iIAPYLOaAo1WeGYAUtYOnmKq', '2025-05-31 15:39:27.177946');


--
-- TOC entry 4041 (class 0 OID 25207)
-- Dependencies: 270
-- Data for Name: users_enhanced; Type: TABLE DATA; Schema: public; Owner: veza
--



--
-- TOC entry 4130 (class 0 OID 0)
-- Dependencies: 267
-- Name: audit_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."audit_logs_id_seq"', 1, false);


--
-- TOC entry 4131 (class 0 OID 0)
-- Dependencies: 245
-- Name: categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."categories_id_seq"', 18, true);


--
-- TOC entry 4132 (class 0 OID 0)
-- Dependencies: 221
-- Name: files_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."files_id_seq"', 1, true);


--
-- TOC entry 4133 (class 0 OID 0)
-- Dependencies: 223
-- Name: internal_documents_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."internal_documents_id_seq"', 1, false);


--
-- TOC entry 4134 (class 0 OID 0)
-- Dependencies: 237
-- Name: listings_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('"public"."listings_id_seq"', 6, true);


--
-- TOC entry 4135 (class 0 OID 0)
-- Dependencies: 276
-- Name: message_mentions_enhanced_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."message_mentions_enhanced_id_seq"', 1, false);


--
-- TOC entry 4136 (class 0 OID 0)
-- Dependencies: 287
-- Name: message_mentions_secure_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."message_mentions_secure_id_seq"', 1, false);


--
-- TOC entry 4137 (class 0 OID 0)
-- Dependencies: 274
-- Name: message_reactions_enhanced_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."message_reactions_enhanced_id_seq"', 1, false);


--
-- TOC entry 4138 (class 0 OID 0)
-- Dependencies: 257
-- Name: message_reactions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."message_reactions_id_seq"', 1, false);


--
-- TOC entry 4139 (class 0 OID 0)
-- Dependencies: 272
-- Name: messages_enhanced_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."messages_enhanced_id_seq"', 1, false);


--
-- TOC entry 4140 (class 0 OID 0)
-- Dependencies: 227
-- Name: messages_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."messages_id_seq"', 126, true);


--
-- TOC entry 4141 (class 0 OID 0)
-- Dependencies: 249
-- Name: migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."migrations_id_seq"', 3, true);


--
-- TOC entry 4142 (class 0 OID 0)
-- Dependencies: 263
-- Name: notifications_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."notifications_id_seq"', 1, false);


--
-- TOC entry 4143 (class 0 OID 0)
-- Dependencies: 239
-- Name: offers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('"public"."offers_id_seq"', 5, true);


--
-- TOC entry 4144 (class 0 OID 0)
-- Dependencies: 247
-- Name: product_documents_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."product_documents_id_seq"', 1, false);


--
-- TOC entry 4145 (class 0 OID 0)
-- Dependencies: 241
-- Name: products_id_seq1; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('"public"."products_id_seq1"', 21, true);


--
-- TOC entry 4146 (class 0 OID 0)
-- Dependencies: 253
-- Name: refresh_tokens_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('"public"."refresh_tokens_id_seq"', 54, true);


--
-- TOC entry 4147 (class 0 OID 0)
-- Dependencies: 261
-- Name: room_members_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."room_members_id_seq"', 1, false);


--
-- TOC entry 4148 (class 0 OID 0)
-- Dependencies: 225
-- Name: rooms_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."rooms_id_seq"', 2, true);


--
-- TOC entry 4149 (class 0 OID 0)
-- Dependencies: 255
-- Name: sanctions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."sanctions_id_seq"', 1, false);


--
-- TOC entry 4150 (class 0 OID 0)
-- Dependencies: 282
-- Name: security_events_enhanced_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."security_events_enhanced_id_seq"', 1, false);


--
-- TOC entry 4151 (class 0 OID 0)
-- Dependencies: 285
-- Name: security_events_secure_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."security_events_secure_id_seq"', 1, false);


--
-- TOC entry 4152 (class 0 OID 0)
-- Dependencies: 231
-- Name: shared_ressources_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."shared_ressources_id_seq"', 8, true);


--
-- TOC entry 4153 (class 0 OID 0)
-- Dependencies: 233
-- Name: tags_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('"public"."tags_id_seq"', 6, true);


--
-- TOC entry 4154 (class 0 OID 0)
-- Dependencies: 229
-- Name: tracks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."tracks_id_seq"', 15, true);


--
-- TOC entry 4155 (class 0 OID 0)
-- Dependencies: 279
-- Name: user_blocks_enhanced_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."user_blocks_enhanced_id_seq"', 1, false);


--
-- TOC entry 4156 (class 0 OID 0)
-- Dependencies: 259
-- Name: user_blocks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."user_blocks_id_seq"', 1, false);


--
-- TOC entry 4157 (class 0 OID 0)
-- Dependencies: 289
-- Name: user_blocks_secure_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."user_blocks_secure_id_seq"', 1, false);


--
-- TOC entry 4158 (class 0 OID 0)
-- Dependencies: 243
-- Name: user_products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('"public"."user_products_id_seq"', 9, true);


--
-- TOC entry 4159 (class 0 OID 0)
-- Dependencies: 265
-- Name: user_sessions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."user_sessions_id_seq"', 1, false);


--
-- TOC entry 4160 (class 0 OID 0)
-- Dependencies: 269
-- Name: users_enhanced_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."users_enhanced_id_seq"', 1, false);


--
-- TOC entry 4161 (class 0 OID 0)
-- Dependencies: 219
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."users_id_seq"', 12, true);


--
-- TOC entry 4162 (class 0 OID 0)
-- Dependencies: 251
-- Name: users_id_seq1; Type: SEQUENCE SET; Schema: public; Owner: veza
--

SELECT pg_catalog.setval('"public"."users_id_seq1"', 15, true);


--
-- TOC entry 3661 (class 2606 OID 24839)
-- Name: categories categories_name_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_name_key" UNIQUE ("name");


--
-- TOC entry 3663 (class 2606 OID 24837)
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3620 (class 2606 OID 16444)
-- Name: files files_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."files"
    ADD CONSTRAINT "files_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3622 (class 2606 OID 16459)
-- Name: internal_documents internal_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."internal_documents"
    ADD CONSTRAINT "internal_documents_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3648 (class 2606 OID 24717)
-- Name: listings listings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."listings"
    ADD CONSTRAINT "listings_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3747 (class 2606 OID 25317)
-- Name: message_mentions_enhanced message_mentions_enhanced_message_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_mentions_enhanced"
    ADD CONSTRAINT "message_mentions_enhanced_message_id_user_id_key" UNIQUE ("message_id", "user_id");


--
-- TOC entry 3749 (class 2606 OID 25315)
-- Name: message_mentions_enhanced message_mentions_enhanced_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_mentions_enhanced"
    ADD CONSTRAINT "message_mentions_enhanced_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3777 (class 2606 OID 25655)
-- Name: message_mentions_secure message_mentions_secure_message_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_mentions_secure"
    ADD CONSTRAINT "message_mentions_secure_message_id_user_id_key" UNIQUE ("message_id", "user_id");


--
-- TOC entry 3779 (class 2606 OID 25653)
-- Name: message_mentions_secure message_mentions_secure_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_mentions_secure"
    ADD CONSTRAINT "message_mentions_secure_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3742 (class 2606 OID 25296)
-- Name: message_reactions_enhanced message_reactions_enhanced_message_id_user_id_emoji_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_reactions_enhanced"
    ADD CONSTRAINT "message_reactions_enhanced_message_id_user_id_emoji_key" UNIQUE ("message_id", "user_id", "emoji");


--
-- TOC entry 3744 (class 2606 OID 25294)
-- Name: message_reactions_enhanced message_reactions_enhanced_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_reactions_enhanced"
    ADD CONSTRAINT "message_reactions_enhanced_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3693 (class 2606 OID 25016)
-- Name: message_reactions message_reactions_message_id_user_id_reaction_type_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_reactions"
    ADD CONSTRAINT "message_reactions_message_id_user_id_reaction_type_key" UNIQUE ("message_id", "user_id", "reaction_type");


--
-- TOC entry 3695 (class 2606 OID 25014)
-- Name: message_reactions message_reactions_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_reactions"
    ADD CONSTRAINT "message_reactions_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3738 (class 2606 OID 25266)
-- Name: messages_enhanced messages_enhanced_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."messages_enhanced"
    ADD CONSTRAINT "messages_enhanced_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3634 (class 2606 OID 16487)
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3669 (class 2606 OID 24893)
-- Name: migrations migrations_filename_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."migrations"
    ADD CONSTRAINT "migrations_filename_key" UNIQUE ("filename");


--
-- TOC entry 3671 (class 2606 OID 24891)
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."migrations"
    ADD CONSTRAINT "migrations_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3713 (class 2606 OID 25087)
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3650 (class 2606 OID 24738)
-- Name: offers offers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."offers"
    ADD CONSTRAINT "offers_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3667 (class 2606 OID 24852)
-- Name: product_documents product_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."product_documents"
    ADD CONSTRAINT "product_documents_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3655 (class 2606 OID 24780)
-- Name: products products_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_name_key" UNIQUE ("name");


--
-- TOC entry 3657 (class 2606 OID 24778)
-- Name: products products_pkey1; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey1" PRIMARY KEY ("id");


--
-- TOC entry 3682 (class 2606 OID 24964)
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3684 (class 2606 OID 24966)
-- Name: refresh_tokens refresh_tokens_token_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_token_key" UNIQUE ("token");


--
-- TOC entry 3686 (class 2606 OID 24968)
-- Name: refresh_tokens refresh_tokens_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_user_id_key" UNIQUE ("user_id");


--
-- TOC entry 3644 (class 2606 OID 16564)
-- Name: ressource_tags ressource_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."ressource_tags"
    ADD CONSTRAINT "ressource_tags_pkey" PRIMARY KEY ("ressource_id", "tag_id");


--
-- TOC entry 3751 (class 2606 OID 25335)
-- Name: room_members_enhanced room_members_enhanced_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."room_members_enhanced"
    ADD CONSTRAINT "room_members_enhanced_pkey" PRIMARY KEY ("room_id", "user_id");


--
-- TOC entry 3706 (class 2606 OID 25061)
-- Name: room_members room_members_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."room_members"
    ADD CONSTRAINT "room_members_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3708 (class 2606 OID 25063)
-- Name: room_members room_members_room_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."room_members"
    ADD CONSTRAINT "room_members_room_id_user_id_key" UNIQUE ("room_id", "user_id");


--
-- TOC entry 3733 (class 2606 OID 25242)
-- Name: rooms_enhanced rooms_enhanced_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."rooms_enhanced"
    ADD CONSTRAINT "rooms_enhanced_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3626 (class 2606 OID 16477)
-- Name: rooms rooms_name_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."rooms"
    ADD CONSTRAINT "rooms_name_key" UNIQUE ("name");


--
-- TOC entry 3628 (class 2606 OID 16475)
-- Name: rooms rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."rooms"
    ADD CONSTRAINT "rooms_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3690 (class 2606 OID 24994)
-- Name: sanctions sanctions_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."sanctions"
    ADD CONSTRAINT "sanctions_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3763 (class 2606 OID 25399)
-- Name: security_events_enhanced security_events_enhanced_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."security_events_enhanced"
    ADD CONSTRAINT "security_events_enhanced_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3774 (class 2606 OID 25634)
-- Name: security_events_secure security_events_secure_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."security_events_secure"
    ADD CONSTRAINT "security_events_secure_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3646 (class 2606 OID 16579)
-- Name: shared_ressource_tags shared_ressource_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shared_ressource_tags"
    ADD CONSTRAINT "shared_ressource_tags_pkey" PRIMARY KEY ("shared_ressource_id", "tag_id");


--
-- TOC entry 3638 (class 2606 OID 16541)
-- Name: shared_ressources shared_ressources_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."shared_ressources"
    ADD CONSTRAINT "shared_ressources_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3640 (class 2606 OID 16559)
-- Name: tags tags_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."tags"
    ADD CONSTRAINT "tags_name_key" UNIQUE ("name");


--
-- TOC entry 3642 (class 2606 OID 16557)
-- Name: tags tags_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."tags"
    ADD CONSTRAINT "tags_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3636 (class 2606 OID 16508)
-- Name: tracks tracks_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."tracks"
    ADD CONSTRAINT "tracks_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3699 (class 2606 OID 25038)
-- Name: user_blocks user_blocks_blocker_id_blocked_id_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks"
    ADD CONSTRAINT "user_blocks_blocker_id_blocked_id_key" UNIQUE ("blocker_id", "blocked_id");


--
-- TOC entry 3753 (class 2606 OID 25358)
-- Name: user_blocks_enhanced user_blocks_enhanced_blocker_id_blocked_id_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks_enhanced"
    ADD CONSTRAINT "user_blocks_enhanced_blocker_id_blocked_id_key" UNIQUE ("blocker_id", "blocked_id");


--
-- TOC entry 3755 (class 2606 OID 25356)
-- Name: user_blocks_enhanced user_blocks_enhanced_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks_enhanced"
    ADD CONSTRAINT "user_blocks_enhanced_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3701 (class 2606 OID 25036)
-- Name: user_blocks user_blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks"
    ADD CONSTRAINT "user_blocks_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3782 (class 2606 OID 25678)
-- Name: user_blocks_secure user_blocks_secure_blocker_id_blocked_id_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks_secure"
    ADD CONSTRAINT "user_blocks_secure_blocker_id_blocked_id_key" UNIQUE ("blocker_id", "blocked_id");


--
-- TOC entry 3784 (class 2606 OID 25676)
-- Name: user_blocks_secure user_blocks_secure_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks_secure"
    ADD CONSTRAINT "user_blocks_secure_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3659 (class 2606 OID 24795)
-- Name: user_products user_products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."user_products"
    ADD CONSTRAINT "user_products_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3759 (class 2606 OID 25379)
-- Name: user_sessions_enhanced user_sessions_enhanced_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_sessions_enhanced"
    ADD CONSTRAINT "user_sessions_enhanced_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3761 (class 2606 OID 25381)
-- Name: user_sessions_enhanced user_sessions_enhanced_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_sessions_enhanced"
    ADD CONSTRAINT "user_sessions_enhanced_token_hash_key" UNIQUE ("token_hash");


--
-- TOC entry 3719 (class 2606 OID 25107)
-- Name: user_sessions user_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_sessions"
    ADD CONSTRAINT "user_sessions_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3767 (class 2606 OID 25612)
-- Name: user_sessions_secure user_sessions_secure_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_sessions_secure"
    ADD CONSTRAINT "user_sessions_secure_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3769 (class 2606 OID 25616)
-- Name: user_sessions_secure user_sessions_secure_refresh_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_sessions_secure"
    ADD CONSTRAINT "user_sessions_secure_refresh_token_hash_key" UNIQUE ("refresh_token_hash");


--
-- TOC entry 3771 (class 2606 OID 25614)
-- Name: user_sessions_secure user_sessions_secure_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_sessions_secure"
    ADD CONSTRAINT "user_sessions_secure_token_hash_key" UNIQUE ("token_hash");


--
-- TOC entry 3721 (class 2606 OID 25109)
-- Name: user_sessions user_sessions_session_token_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_sessions"
    ADD CONSTRAINT "user_sessions_session_token_key" UNIQUE ("session_token");


--
-- TOC entry 3614 (class 2606 OID 16403)
-- Name: users_backup users_email_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."users_backup"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");


--
-- TOC entry 3676 (class 2606 OID 24945)
-- Name: users users_email_key1; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_key1" UNIQUE ("email");


--
-- TOC entry 3727 (class 2606 OID 25228)
-- Name: users_enhanced users_enhanced_email_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."users_enhanced"
    ADD CONSTRAINT "users_enhanced_email_key" UNIQUE ("email");


--
-- TOC entry 3729 (class 2606 OID 25224)
-- Name: users_enhanced users_enhanced_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."users_enhanced"
    ADD CONSTRAINT "users_enhanced_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3731 (class 2606 OID 25226)
-- Name: users_enhanced users_enhanced_username_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."users_enhanced"
    ADD CONSTRAINT "users_enhanced_username_key" UNIQUE ("username");


--
-- TOC entry 3616 (class 2606 OID 16399)
-- Name: users_backup users_pkey; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."users_backup"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");


--
-- TOC entry 3678 (class 2606 OID 24941)
-- Name: users users_pkey1; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey1" PRIMARY KEY ("id");


--
-- TOC entry 3618 (class 2606 OID 16401)
-- Name: users_backup users_username_key; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."users_backup"
    ADD CONSTRAINT "users_username_key" UNIQUE ("username");


--
-- TOC entry 3680 (class 2606 OID 24943)
-- Name: users users_username_key1; Type: CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_username_key1" UNIQUE ("username");


--
-- TOC entry 3722 (class 1259 OID 25135)
-- Name: idx_audit_logs_action; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_audit_logs_action" ON "public"."audit_logs" USING "btree" ("action");


--
-- TOC entry 3723 (class 1259 OID 25137)
-- Name: idx_audit_logs_created; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_audit_logs_created" ON "public"."audit_logs" USING "btree" ("created_at");


--
-- TOC entry 3724 (class 1259 OID 25136)
-- Name: idx_audit_logs_resource; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_audit_logs_resource" ON "public"."audit_logs" USING "btree" ("resource_type", "resource_id");


--
-- TOC entry 3725 (class 1259 OID 25134)
-- Name: idx_audit_logs_user; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_audit_logs_user" ON "public"."audit_logs" USING "btree" ("user_id");


--
-- TOC entry 3780 (class 1259 OID 25693)
-- Name: idx_blocks_secure_blocker; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_blocks_secure_blocker" ON "public"."user_blocks_secure" USING "btree" ("blocker_id");


--
-- TOC entry 3775 (class 1259 OID 25692)
-- Name: idx_mentions_secure_user; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_mentions_secure_user" ON "public"."message_mentions_secure" USING "btree" ("user_id", "is_read");


--
-- TOC entry 3745 (class 1259 OID 25410)
-- Name: idx_mentions_user_enhanced; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_mentions_user_enhanced" ON "public"."message_mentions_enhanced" USING "btree" ("user_id", "is_read");


--
-- TOC entry 3691 (class 1259 OID 25027)
-- Name: idx_message_reactions_message; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_message_reactions_message" ON "public"."message_reactions" USING "btree" ("message_id");


--
-- TOC entry 3734 (class 1259 OID 25406)
-- Name: idx_messages_dm_enhanced; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_messages_dm_enhanced" ON "public"."messages_enhanced" USING "btree" ("author_id", "recipient_id", "created_at" DESC) WHERE ((("message_type")::"text" = 'direct_message'::"text") AND (("status")::"text" <> 'deleted'::"text"));


--
-- TOC entry 3735 (class 1259 OID 25407)
-- Name: idx_messages_dm_reverse_enhanced; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_messages_dm_reverse_enhanced" ON "public"."messages_enhanced" USING "btree" ("recipient_id", "author_id", "created_at" DESC) WHERE ((("message_type")::"text" = 'direct_message'::"text") AND (("status")::"text" <> 'deleted'::"text"));


--
-- TOC entry 3629 (class 1259 OID 25147)
-- Name: idx_messages_edited; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_messages_edited" ON "public"."messages" USING "btree" ("is_edited") WHERE ("is_edited" = true);


--
-- TOC entry 3630 (class 1259 OID 25420)
-- Name: idx_messages_pinned; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_messages_pinned" ON "public"."messages" USING "btree" ("is_pinned") WHERE ("is_pinned" = true);


--
-- TOC entry 3631 (class 1259 OID 25146)
-- Name: idx_messages_reply; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_messages_reply" ON "public"."messages" USING "btree" ("reply_to_id");


--
-- TOC entry 3736 (class 1259 OID 25405)
-- Name: idx_messages_room_enhanced; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_messages_room_enhanced" ON "public"."messages_enhanced" USING "btree" ("room_id", "created_at" DESC) WHERE ((("message_type")::"text" = 'room_message'::"text") AND (("status")::"text" <> 'deleted'::"text"));


--
-- TOC entry 3632 (class 1259 OID 25145)
-- Name: idx_messages_type; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_messages_type" ON "public"."messages" USING "btree" ("message_type");


--
-- TOC entry 3709 (class 1259 OID 25095)
-- Name: idx_notifications_type; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_notifications_type" ON "public"."notifications" USING "btree" ("type");


--
-- TOC entry 3710 (class 1259 OID 25094)
-- Name: idx_notifications_unread; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_notifications_unread" ON "public"."notifications" USING "btree" ("user_id", "is_read") WHERE ("is_read" = false);


--
-- TOC entry 3711 (class 1259 OID 25093)
-- Name: idx_notifications_user; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_notifications_user" ON "public"."notifications" USING "btree" ("user_id");


--
-- TOC entry 3664 (class 1259 OID 24859)
-- Name: idx_product_documents_file_type; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_product_documents_file_type" ON "public"."product_documents" USING "btree" ("file_type");


--
-- TOC entry 3665 (class 1259 OID 24858)
-- Name: idx_product_documents_product_id; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_product_documents_product_id" ON "public"."product_documents" USING "btree" ("product_id");


--
-- TOC entry 3651 (class 1259 OID 24879)
-- Name: idx_products_category_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_products_category_id" ON "public"."products" USING "btree" ("category_id");


--
-- TOC entry 3652 (class 1259 OID 24880)
-- Name: idx_products_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_products_status" ON "public"."products" USING "btree" ("status");


--
-- TOC entry 3653 (class 1259 OID 24881)
-- Name: idx_products_updated_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_products_updated_at" ON "public"."products" USING "btree" ("updated_at");


--
-- TOC entry 3739 (class 1259 OID 25408)
-- Name: idx_reactions_message_enhanced; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_reactions_message_enhanced" ON "public"."message_reactions_enhanced" USING "btree" ("message_id");


--
-- TOC entry 3740 (class 1259 OID 25409)
-- Name: idx_reactions_user_enhanced; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_reactions_user_enhanced" ON "public"."message_reactions_enhanced" USING "btree" ("user_id");


--
-- TOC entry 3702 (class 1259 OID 25076)
-- Name: idx_room_members_role; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_room_members_role" ON "public"."room_members" USING "btree" ("room_id", "role");


--
-- TOC entry 3703 (class 1259 OID 25074)
-- Name: idx_room_members_room; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_room_members_room" ON "public"."room_members" USING "btree" ("room_id");


--
-- TOC entry 3704 (class 1259 OID 25075)
-- Name: idx_room_members_user; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_room_members_user" ON "public"."room_members" USING "btree" ("user_id");


--
-- TOC entry 3623 (class 1259 OID 25051)
-- Name: idx_rooms_name; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_rooms_name" ON "public"."rooms" USING "btree" ("name");


--
-- TOC entry 3624 (class 1259 OID 25052)
-- Name: idx_rooms_private; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_rooms_private" ON "public"."rooms" USING "btree" ("is_private");


--
-- TOC entry 3687 (class 1259 OID 25006)
-- Name: idx_sanctions_active; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_sanctions_active" ON "public"."sanctions" USING "btree" ("user_id", "is_active") WHERE ("is_active" = true);


--
-- TOC entry 3688 (class 1259 OID 25005)
-- Name: idx_sanctions_user_id; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_sanctions_user_id" ON "public"."sanctions" USING "btree" ("user_id");


--
-- TOC entry 3772 (class 1259 OID 25691)
-- Name: idx_security_events_user; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_security_events_user" ON "public"."security_events_secure" USING "btree" ("user_id", "created_at" DESC);


--
-- TOC entry 3764 (class 1259 OID 25690)
-- Name: idx_sessions_secure_expires; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_sessions_secure_expires" ON "public"."user_sessions_secure" USING "btree" ("expires_at");


--
-- TOC entry 3765 (class 1259 OID 25689)
-- Name: idx_sessions_secure_user; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_sessions_secure_user" ON "public"."user_sessions_secure" USING "btree" ("user_id", "is_active");


--
-- TOC entry 3756 (class 1259 OID 25412)
-- Name: idx_sessions_token_enhanced; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_sessions_token_enhanced" ON "public"."user_sessions_enhanced" USING "btree" ("token_hash");


--
-- TOC entry 3757 (class 1259 OID 25411)
-- Name: idx_sessions_user_enhanced; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_sessions_user_enhanced" ON "public"."user_sessions_enhanced" USING "btree" ("user_id", "is_active");


--
-- TOC entry 3696 (class 1259 OID 25050)
-- Name: idx_user_blocks_blocked; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_user_blocks_blocked" ON "public"."user_blocks" USING "btree" ("blocked_id");


--
-- TOC entry 3697 (class 1259 OID 25049)
-- Name: idx_user_blocks_blocker; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_user_blocks_blocker" ON "public"."user_blocks" USING "btree" ("blocker_id");


--
-- TOC entry 3714 (class 1259 OID 25117)
-- Name: idx_user_sessions_active; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_user_sessions_active" ON "public"."user_sessions" USING "btree" ("user_id", "is_active") WHERE ("is_active" = true);


--
-- TOC entry 3715 (class 1259 OID 25118)
-- Name: idx_user_sessions_expires; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_user_sessions_expires" ON "public"."user_sessions" USING "btree" ("expires_at");


--
-- TOC entry 3716 (class 1259 OID 25116)
-- Name: idx_user_sessions_token; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_user_sessions_token" ON "public"."user_sessions" USING "btree" ("session_token");


--
-- TOC entry 3717 (class 1259 OID 25115)
-- Name: idx_user_sessions_user; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_user_sessions_user" ON "public"."user_sessions" USING "btree" ("user_id");


--
-- TOC entry 3672 (class 1259 OID 24948)
-- Name: idx_users_created_at; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_users_created_at" ON "public"."users" USING "btree" ("created_at");


--
-- TOC entry 3611 (class 1259 OID 24894)
-- Name: idx_users_email; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_users_email" ON "public"."users_backup" USING "btree" ("email");


--
-- TOC entry 3673 (class 1259 OID 24947)
-- Name: idx_users_is_active; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_users_is_active" ON "public"."users" USING "btree" ("is_active");


--
-- TOC entry 3674 (class 1259 OID 25153)
-- Name: idx_users_status; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_users_status" ON "public"."users" USING "btree" ("status");


--
-- TOC entry 3612 (class 1259 OID 24895)
-- Name: idx_users_username; Type: INDEX; Schema: public; Owner: veza
--

CREATE INDEX "idx_users_username" ON "public"."users_backup" USING "btree" ("username");


--
-- TOC entry 3839 (class 2620 OID 25697)
-- Name: messages trigger_handle_mentions_secure; Type: TRIGGER; Schema: public; Owner: veza
--

CREATE TRIGGER "trigger_handle_mentions_secure" AFTER INSERT ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "public"."handle_mentions_secure"();


--
-- TOC entry 3841 (class 2620 OID 24883)
-- Name: categories update_categories_updated_at; Type: TRIGGER; Schema: public; Owner: veza
--

CREATE TRIGGER "update_categories_updated_at" BEFORE UPDATE ON "public"."categories" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();


--
-- TOC entry 3840 (class 2620 OID 24882)
-- Name: products update_products_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "update_products_updated_at" BEFORE UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();


--
-- TOC entry 3844 (class 2620 OID 25414)
-- Name: rooms_enhanced update_rooms_enhanced_updated_at; Type: TRIGGER; Schema: public; Owner: veza
--

CREATE TRIGGER "update_rooms_enhanced_updated_at" BEFORE UPDATE ON "public"."rooms_enhanced" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();


--
-- TOC entry 3843 (class 2620 OID 25413)
-- Name: users_enhanced update_users_enhanced_updated_at; Type: TRIGGER; Schema: public; Owner: veza
--

CREATE TRIGGER "update_users_enhanced_updated_at" BEFORE UPDATE ON "public"."users_enhanced" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();


--
-- TOC entry 3842 (class 2620 OID 24950)
-- Name: users update_users_updated_at; Type: TRIGGER; Schema: public; Owner: veza
--

CREATE TRIGGER "update_users_updated_at" BEFORE UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();


--
-- TOC entry 3816 (class 2606 OID 25129)
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");


--
-- TOC entry 3785 (class 2606 OID 24816)
-- Name: files files_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."files"
    ADD CONSTRAINT "files_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."user_products"("id") ON DELETE CASCADE;


--
-- TOC entry 3786 (class 2606 OID 24821)
-- Name: internal_documents internal_documents_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."internal_documents"
    ADD CONSTRAINT "internal_documents_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."user_products"("id") ON DELETE CASCADE;


--
-- TOC entry 3796 (class 2606 OID 24806)
-- Name: listings listings_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."listings"
    ADD CONSTRAINT "listings_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;


--
-- TOC entry 3797 (class 2606 OID 24718)
-- Name: listings listings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."listings"
    ADD CONSTRAINT "listings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users_backup"("id") ON DELETE CASCADE;


--
-- TOC entry 3824 (class 2606 OID 25318)
-- Name: message_mentions_enhanced message_mentions_enhanced_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_mentions_enhanced"
    ADD CONSTRAINT "message_mentions_enhanced_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."messages_enhanced"("id") ON DELETE CASCADE;


--
-- TOC entry 3825 (class 2606 OID 25323)
-- Name: message_mentions_enhanced message_mentions_enhanced_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_mentions_enhanced"
    ADD CONSTRAINT "message_mentions_enhanced_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users_enhanced"("id") ON DELETE CASCADE;


--
-- TOC entry 3835 (class 2606 OID 25656)
-- Name: message_mentions_secure message_mentions_secure_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_mentions_secure"
    ADD CONSTRAINT "message_mentions_secure_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."messages"("id") ON DELETE CASCADE;


--
-- TOC entry 3836 (class 2606 OID 25661)
-- Name: message_mentions_secure message_mentions_secure_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_mentions_secure"
    ADD CONSTRAINT "message_mentions_secure_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;


--
-- TOC entry 3822 (class 2606 OID 25297)
-- Name: message_reactions_enhanced message_reactions_enhanced_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_reactions_enhanced"
    ADD CONSTRAINT "message_reactions_enhanced_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."messages_enhanced"("id") ON DELETE CASCADE;


--
-- TOC entry 3823 (class 2606 OID 25302)
-- Name: message_reactions_enhanced message_reactions_enhanced_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_reactions_enhanced"
    ADD CONSTRAINT "message_reactions_enhanced_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users_enhanced"("id") ON DELETE CASCADE;


--
-- TOC entry 3808 (class 2606 OID 25017)
-- Name: message_reactions message_reactions_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_reactions"
    ADD CONSTRAINT "message_reactions_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."messages"("id") ON DELETE CASCADE;


--
-- TOC entry 3809 (class 2606 OID 25022)
-- Name: message_reactions message_reactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."message_reactions"
    ADD CONSTRAINT "message_reactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;


--
-- TOC entry 3818 (class 2606 OID 25267)
-- Name: messages_enhanced messages_enhanced_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."messages_enhanced"
    ADD CONSTRAINT "messages_enhanced_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."users_enhanced"("id") ON DELETE CASCADE;


--
-- TOC entry 3819 (class 2606 OID 25282)
-- Name: messages_enhanced messages_enhanced_parent_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."messages_enhanced"
    ADD CONSTRAINT "messages_enhanced_parent_message_id_fkey" FOREIGN KEY ("parent_message_id") REFERENCES "public"."messages_enhanced"("id") ON DELETE SET NULL;


--
-- TOC entry 3820 (class 2606 OID 25277)
-- Name: messages_enhanced messages_enhanced_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."messages_enhanced"
    ADD CONSTRAINT "messages_enhanced_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "public"."users_enhanced"("id") ON DELETE CASCADE;


--
-- TOC entry 3821 (class 2606 OID 25272)
-- Name: messages_enhanced messages_enhanced_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."messages_enhanced"
    ADD CONSTRAINT "messages_enhanced_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "public"."rooms_enhanced"("id") ON DELETE CASCADE;


--
-- TOC entry 3787 (class 2606 OID 24974)
-- Name: messages messages_from_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_from_user_fkey" FOREIGN KEY ("from_user") REFERENCES "public"."users"("id") ON DELETE CASCADE;


--
-- TOC entry 3788 (class 2606 OID 25140)
-- Name: messages messages_reply_to_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_reply_to_id_fkey" FOREIGN KEY ("reply_to_id") REFERENCES "public"."messages"("id");


--
-- TOC entry 3789 (class 2606 OID 24979)
-- Name: messages messages_to_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_to_user_fkey" FOREIGN KEY ("to_user") REFERENCES "public"."users"("id") ON DELETE SET NULL;


--
-- TOC entry 3814 (class 2606 OID 25088)
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;


--
-- TOC entry 3798 (class 2606 OID 24744)
-- Name: offers offers_from_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."offers"
    ADD CONSTRAINT "offers_from_user_id_fkey" FOREIGN KEY ("from_user_id") REFERENCES "public"."users_backup"("id") ON DELETE CASCADE;


--
-- TOC entry 3799 (class 2606 OID 24739)
-- Name: offers offers_listing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."offers"
    ADD CONSTRAINT "offers_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "public"."listings"("id") ON DELETE CASCADE;


--
-- TOC entry 3800 (class 2606 OID 24811)
-- Name: offers offers_proposed_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."offers"
    ADD CONSTRAINT "offers_proposed_product_id_fkey" FOREIGN KEY ("proposed_product_id") REFERENCES "public"."user_products"("id") ON DELETE CASCADE;


--
-- TOC entry 3804 (class 2606 OID 24853)
-- Name: product_documents product_documents_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."product_documents"
    ADD CONSTRAINT "product_documents_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;


--
-- TOC entry 3801 (class 2606 OID 24863)
-- Name: products products_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id");


--
-- TOC entry 3805 (class 2606 OID 24969)
-- Name: refresh_tokens refresh_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;


--
-- TOC entry 3792 (class 2606 OID 16565)
-- Name: ressource_tags ressource_tags_ressource_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."ressource_tags"
    ADD CONSTRAINT "ressource_tags_ressource_id_fkey" FOREIGN KEY ("ressource_id") REFERENCES "public"."shared_ressources"("id") ON DELETE CASCADE;


--
-- TOC entry 3793 (class 2606 OID 16570)
-- Name: ressource_tags ressource_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."ressource_tags"
    ADD CONSTRAINT "ressource_tags_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "public"."tags"("id") ON DELETE CASCADE;


--
-- TOC entry 3826 (class 2606 OID 25336)
-- Name: room_members_enhanced room_members_enhanced_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."room_members_enhanced"
    ADD CONSTRAINT "room_members_enhanced_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "public"."rooms_enhanced"("id") ON DELETE CASCADE;


--
-- TOC entry 3827 (class 2606 OID 25341)
-- Name: room_members_enhanced room_members_enhanced_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."room_members_enhanced"
    ADD CONSTRAINT "room_members_enhanced_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users_enhanced"("id") ON DELETE CASCADE;


--
-- TOC entry 3812 (class 2606 OID 25064)
-- Name: room_members room_members_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."room_members"
    ADD CONSTRAINT "room_members_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "public"."rooms"("id") ON DELETE CASCADE;


--
-- TOC entry 3813 (class 2606 OID 25069)
-- Name: room_members room_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."room_members"
    ADD CONSTRAINT "room_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;


--
-- TOC entry 3817 (class 2606 OID 25243)
-- Name: rooms_enhanced rooms_enhanced_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."rooms_enhanced"
    ADD CONSTRAINT "rooms_enhanced_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."users_enhanced"("id") ON DELETE CASCADE;


--
-- TOC entry 3806 (class 2606 OID 25000)
-- Name: sanctions sanctions_moderator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."sanctions"
    ADD CONSTRAINT "sanctions_moderator_id_fkey" FOREIGN KEY ("moderator_id") REFERENCES "public"."users"("id");


--
-- TOC entry 3807 (class 2606 OID 24995)
-- Name: sanctions sanctions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."sanctions"
    ADD CONSTRAINT "sanctions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;


--
-- TOC entry 3831 (class 2606 OID 25400)
-- Name: security_events_enhanced security_events_enhanced_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."security_events_enhanced"
    ADD CONSTRAINT "security_events_enhanced_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users_enhanced"("id") ON DELETE SET NULL;


--
-- TOC entry 3833 (class 2606 OID 25640)
-- Name: security_events_secure security_events_secure_resolved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."security_events_secure"
    ADD CONSTRAINT "security_events_secure_resolved_by_fkey" FOREIGN KEY ("resolved_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;


--
-- TOC entry 3834 (class 2606 OID 25635)
-- Name: security_events_secure security_events_secure_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."security_events_secure"
    ADD CONSTRAINT "security_events_secure_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;


--
-- TOC entry 3794 (class 2606 OID 16580)
-- Name: shared_ressource_tags shared_ressource_tags_shared_ressource_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shared_ressource_tags"
    ADD CONSTRAINT "shared_ressource_tags_shared_ressource_id_fkey" FOREIGN KEY ("shared_ressource_id") REFERENCES "public"."shared_ressources"("id") ON DELETE CASCADE;


--
-- TOC entry 3795 (class 2606 OID 16585)
-- Name: shared_ressource_tags shared_ressource_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shared_ressource_tags"
    ADD CONSTRAINT "shared_ressource_tags_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "public"."tags"("id") ON DELETE CASCADE;


--
-- TOC entry 3791 (class 2606 OID 16542)
-- Name: shared_ressources shared_ressources_uploader_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."shared_ressources"
    ADD CONSTRAINT "shared_ressources_uploader_id_fkey" FOREIGN KEY ("uploader_id") REFERENCES "public"."users_backup"("id");


--
-- TOC entry 3790 (class 2606 OID 16509)
-- Name: tracks tracks_uploader_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."tracks"
    ADD CONSTRAINT "tracks_uploader_id_fkey" FOREIGN KEY ("uploader_id") REFERENCES "public"."users_backup"("id");


--
-- TOC entry 3810 (class 2606 OID 25044)
-- Name: user_blocks user_blocks_blocked_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks"
    ADD CONSTRAINT "user_blocks_blocked_id_fkey" FOREIGN KEY ("blocked_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;


--
-- TOC entry 3811 (class 2606 OID 25039)
-- Name: user_blocks user_blocks_blocker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks"
    ADD CONSTRAINT "user_blocks_blocker_id_fkey" FOREIGN KEY ("blocker_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;


--
-- TOC entry 3828 (class 2606 OID 25364)
-- Name: user_blocks_enhanced user_blocks_enhanced_blocked_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks_enhanced"
    ADD CONSTRAINT "user_blocks_enhanced_blocked_id_fkey" FOREIGN KEY ("blocked_id") REFERENCES "public"."users_enhanced"("id") ON DELETE CASCADE;


--
-- TOC entry 3829 (class 2606 OID 25359)
-- Name: user_blocks_enhanced user_blocks_enhanced_blocker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks_enhanced"
    ADD CONSTRAINT "user_blocks_enhanced_blocker_id_fkey" FOREIGN KEY ("blocker_id") REFERENCES "public"."users_enhanced"("id") ON DELETE CASCADE;


--
-- TOC entry 3837 (class 2606 OID 25684)
-- Name: user_blocks_secure user_blocks_secure_blocked_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks_secure"
    ADD CONSTRAINT "user_blocks_secure_blocked_id_fkey" FOREIGN KEY ("blocked_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;


--
-- TOC entry 3838 (class 2606 OID 25679)
-- Name: user_blocks_secure user_blocks_secure_blocker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_blocks_secure"
    ADD CONSTRAINT "user_blocks_secure_blocker_id_fkey" FOREIGN KEY ("blocker_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;


--
-- TOC entry 3802 (class 2606 OID 24801)
-- Name: user_products user_products_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."user_products"
    ADD CONSTRAINT "user_products_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;


--
-- TOC entry 3803 (class 2606 OID 24796)
-- Name: user_products user_products_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."user_products"
    ADD CONSTRAINT "user_products_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users_backup"("id") ON DELETE CASCADE;


--
-- TOC entry 3830 (class 2606 OID 25382)
-- Name: user_sessions_enhanced user_sessions_enhanced_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_sessions_enhanced"
    ADD CONSTRAINT "user_sessions_enhanced_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users_enhanced"("id") ON DELETE CASCADE;


--
-- TOC entry 3832 (class 2606 OID 25617)
-- Name: user_sessions_secure user_sessions_secure_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_sessions_secure"
    ADD CONSTRAINT "user_sessions_secure_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;


--
-- TOC entry 3815 (class 2606 OID 25110)
-- Name: user_sessions user_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: veza
--

ALTER TABLE ONLY "public"."user_sessions"
    ADD CONSTRAINT "user_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;


--
-- TOC entry 4074 (class 0 OID 0)
-- Dependencies: 238
-- Name: TABLE "listings"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."listings" TO "veza";


--
-- TOC entry 4076 (class 0 OID 0)
-- Dependencies: 237
-- Name: SEQUENCE "listings_id_seq"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE "public"."listings_id_seq" TO "veza";


--
-- TOC entry 4090 (class 0 OID 0)
-- Dependencies: 240
-- Name: TABLE "offers"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."offers" TO "veza";


--
-- TOC entry 4092 (class 0 OID 0)
-- Dependencies: 239
-- Name: SEQUENCE "offers_id_seq"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE "public"."offers_id_seq" TO "veza";


--
-- TOC entry 4094 (class 0 OID 0)
-- Dependencies: 242
-- Name: TABLE "products"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."products" TO "veza";


--
-- TOC entry 4096 (class 0 OID 0)
-- Dependencies: 241
-- Name: SEQUENCE "products_id_seq1"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE "public"."products_id_seq1" TO "veza";


--
-- TOC entry 4097 (class 0 OID 0)
-- Dependencies: 254
-- Name: TABLE "refresh_tokens"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."refresh_tokens" TO "veza";


--
-- TOC entry 4099 (class 0 OID 0)
-- Dependencies: 253
-- Name: SEQUENCE "refresh_tokens_id_seq"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE "public"."refresh_tokens_id_seq" TO "veza";


--
-- TOC entry 4100 (class 0 OID 0)
-- Dependencies: 235
-- Name: TABLE "ressource_tags"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."ressource_tags" TO "veza";


--
-- TOC entry 4110 (class 0 OID 0)
-- Dependencies: 236
-- Name: TABLE "shared_ressource_tags"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."shared_ressource_tags" TO "veza";


--
-- TOC entry 4112 (class 0 OID 0)
-- Dependencies: 234
-- Name: TABLE "tags"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."tags" TO "veza";


--
-- TOC entry 4120 (class 0 OID 0)
-- Dependencies: 244
-- Name: TABLE "user_products"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."user_products" TO "veza";


--
-- TOC entry 4122 (class 0 OID 0)
-- Dependencies: 243
-- Name: SEQUENCE "user_products_id_seq"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE "public"."user_products_id_seq" TO "veza";


--
-- TOC entry 2281 (class 826 OID 24754)
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "veza";


--
-- TOC entry 2282 (class 826 OID 24755)
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "veza";


-- Completed on 2025-06-18 22:11:06 UTC

--
-- PostgreSQL database dump complete
--

