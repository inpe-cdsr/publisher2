--
-- PostgreSQL database dump
--

-- Dumped from database version 11.7 (Debian 11.7-2.pgdg100+1)
-- Dumped by pg_dump version 12.0

-- Started on 2021-02-01 19:16:29 UTC

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
-- TOC entry 8 (class 2615 OID 55169)
-- Name: bdc; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA bdc;


ALTER SCHEMA bdc OWNER TO postgres;

--
-- TOC entry 2 (class 3079 OID 55170)
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- TOC entry 5595 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions';


--
-- TOC entry 1921 (class 1247 OID 56749)
-- Name: collection_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.collection_type AS ENUM (
    'cube',
    'collection'
);


ALTER TYPE public.collection_type OWNER TO postgres;

--
-- TOC entry 1924 (class 1247 OID 56754)
-- Name: data_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.data_type AS ENUM (
    'uint8',
    'int8',
    'uint16',
    'int16',
    'uint32',
    'int32',
    'float32',
    'float64'
);


ALTER TYPE public.data_type OWNER TO postgres;

--
-- TOC entry 1468 (class 1255 OID 56771)
-- Name: check_bands_metadata_index(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_bands_metadata_index() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    record RECORD;
    bands_required INTEGER ARRAY;
    bands_size SMALLINT;
    query TEXT;
    i INTEGER;
BEGIN
    IF NEW.metadata ? 'expression' THEN
        -- Ensure that have minimal required parameters to check
        -- We must check if user given bands
        IF NOT NEW.metadata->'expression' ? 'bands' THEN
            RAISE EXCEPTION 'Invalid metadata expression. Expected key "bands".';
        END IF;

        bands_size := jsonb_array_length((NEW.metadata->'expression')->'bands');

        IF bands_size = 0 THEN
            RAISE EXCEPTION 'Expected at least one element in "bands", but got 0';
        END IF;

        bands_required := ARRAY(SELECT * FROM jsonb_array_elements((NEW.metadata->'expression')->'bands'));

        RAISE NOTICE '%', bands_required;

        query := 'SELECT id FROM bdc.bands WHERE id = ANY($1)';

        EXECUTE query USING bands_required;

        GET DIAGNOSTICS i = ROW_COUNT;

        -- Ensure that given bands were found in database.
        IF i != bands_size THEN
            RAISE EXCEPTION 'Mismatch bands. Expected total of % bands (%), got only % bands', bands_size, bands_required, i;
        END IF;

    END IF;

    RETURN NEW;
END;
$_$;


ALTER FUNCTION public.check_bands_metadata_index() OWNER TO postgres;

--
-- TOC entry 1469 (class 1255 OID 56772)
-- Name: update_collection_time(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_collection_time() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Once Item update/insert, calculate the min/max time and update in collections.
    UPDATE bdc.collections
       SET start_date = stats.min_date,
           end_date = stats.max_date,
           extent = stats.extent
      FROM (
        SELECT min(start_date) AS min_date,
               max(end_date) AS max_date,
               ST_SetSRID(ST_Envelope(ST_Extent(geom)), 4326) AS extent
          FROM bdc.items
         WHERE collection_id = NEW.collection_id
      ) stats
      WHERE id = NEW.collection_id;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_collection_time() OWNER TO postgres;

--
-- TOC entry 1470 (class 1255 OID 56773)
-- Name: update_timeline(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_timeline() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Once Item update/insert, calculate the min/max time and update in collections.
    IF NOT EXISTS (SELECT * FROM bdc.timeline WHERE collection_id = NEW.collection_id AND (time_inst = NEW.start_date OR time_inst = NEW.end_date)) THEN
        INSERT INTO bdc.timeline (collection_id, time_inst, created, updated)
             VALUES (NEW.collection_id, NEW.start_date, now(), now()), (NEW.collection_id, NEW.end_date, now(), now())
                 ON CONFLICT DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_timeline() OWNER TO postgres;

SET default_tablespace = '';

--
-- TOC entry 213 (class 1259 OID 56774)
-- Name: applications; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.applications (
    id integer NOT NULL,
    name character varying(64) NOT NULL,
    version character varying(32) NOT NULL,
    uri character varying(255),
    metadata jsonb,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.applications OWNER TO postgres;

--
-- TOC entry 5596 (class 0 OID 0)
-- Dependencies: 213
-- Name: COLUMN applications.metadata; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.applications.metadata IS 'Follow the JSONSchema @jsonschemas/application-metadata.json';


--
-- TOC entry 214 (class 1259 OID 56782)
-- Name: applications_id_seq; Type: SEQUENCE; Schema: bdc; Owner: postgres
--

CREATE SEQUENCE bdc.applications_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bdc.applications_id_seq OWNER TO postgres;

--
-- TOC entry 5597 (class 0 OID 0)
-- Dependencies: 214
-- Name: applications_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.applications_id_seq OWNED BY bdc.applications.id;


--
-- TOC entry 215 (class 1259 OID 56784)
-- Name: band_src; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.band_src (
    band_id integer NOT NULL,
    band_src_id integer NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.band_src OWNER TO postgres;

--
-- TOC entry 216 (class 1259 OID 56789)
-- Name: bands; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.bands (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    common_name character varying(255) NOT NULL,
    description text,
    min_value numeric,
    max_value numeric,
    nodata numeric,
    scale numeric,
    resolution_x numeric,
    resolution_y numeric,
    center_wavelength numeric,
    full_width_half_max numeric,
    collection_id integer,
    resolution_unit_id integer,
    data_type public.data_type,
    mime_type_id integer,
    metadata jsonb,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.bands OWNER TO postgres;

--
-- TOC entry 5598 (class 0 OID 0)
-- Dependencies: 216
-- Name: COLUMN bands.metadata; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.bands.metadata IS 'Follow the JSONSchema @jsonschemas/band-metadata.json';


--
-- TOC entry 217 (class 1259 OID 56797)
-- Name: bands_id_seq; Type: SEQUENCE; Schema: bdc; Owner: postgres
--

CREATE SEQUENCE bdc.bands_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bdc.bands_id_seq OWNER TO postgres;

--
-- TOC entry 5599 (class 0 OID 0)
-- Dependencies: 217
-- Name: bands_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.bands_id_seq OWNED BY bdc.bands.id;


--
-- TOC entry 218 (class 1259 OID 56799)
-- Name: collection_src; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.collection_src (
    collection_id integer NOT NULL,
    collection_src_id integer NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.collection_src OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 56804)
-- Name: collections; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.collections (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    temporal_composition_schema jsonb,
    composite_function_id integer,
    grid_ref_sys_id integer,
    collection_type public.collection_type DEFAULT 'collection'::public.collection_type NOT NULL,
    metadata jsonb,
    is_public boolean DEFAULT true NOT NULL,
    start_date timestamp with time zone,
    end_date timestamp with time zone,
    extent public.geometry(Polygon,4326),
    version integer DEFAULT 1 NOT NULL,
    version_predecessor integer,
    version_successor integer,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.collections OWNER TO postgres;

--
-- TOC entry 5600 (class 0 OID 0)
-- Dependencies: 219
-- Name: COLUMN collections.name; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.collections.name IS 'Collection name internally.';


--
-- TOC entry 5601 (class 0 OID 0)
-- Dependencies: 219
-- Name: COLUMN collections.title; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.collections.title IS 'A human-readable string naming for collection.';


--
-- TOC entry 5602 (class 0 OID 0)
-- Dependencies: 219
-- Name: COLUMN collections.temporal_composition_schema; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.collections.temporal_composition_schema IS 'Follow the JSONSchema @jsonschemas/collection-temporal-composition-schema.json';


--
-- TOC entry 5603 (class 0 OID 0)
-- Dependencies: 219
-- Name: COLUMN collections.composite_function_id; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.collections.composite_function_id IS 'Function schema identifier. Used for data cubes.';


--
-- TOC entry 5604 (class 0 OID 0)
-- Dependencies: 219
-- Name: COLUMN collections.metadata; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.collections.metadata IS 'Follow the JSONSchema @jsonschemas/collection-metadata.json';


--
-- TOC entry 220 (class 1259 OID 56815)
-- Name: collections_id_seq; Type: SEQUENCE; Schema: bdc; Owner: postgres
--

CREATE SEQUENCE bdc.collections_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bdc.collections_id_seq OWNER TO postgres;

--
-- TOC entry 5605 (class 0 OID 0)
-- Dependencies: 220
-- Name: collections_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.collections_id_seq OWNED BY bdc.collections.id;


--
-- TOC entry 221 (class 1259 OID 56817)
-- Name: collections_providers; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.collections_providers (
    provider_id integer NOT NULL,
    collection_id integer NOT NULL,
    active boolean NOT NULL,
    priority smallint NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.collections_providers OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 56822)
-- Name: composite_functions; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.composite_functions (
    id integer NOT NULL,
    name character varying(64) NOT NULL,
    description text NOT NULL,
    alias character varying(6) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.composite_functions OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 56830)
-- Name: composite_functions_id_seq; Type: SEQUENCE; Schema: bdc; Owner: postgres
--

CREATE SEQUENCE bdc.composite_functions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bdc.composite_functions_id_seq OWNER TO postgres;

--
-- TOC entry 5606 (class 0 OID 0)
-- Dependencies: 223
-- Name: composite_functions_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.composite_functions_id_seq OWNED BY bdc.composite_functions.id;


--
-- TOC entry 224 (class 1259 OID 56832)
-- Name: grid_ref_sys; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.grid_ref_sys (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    table_id oid NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.grid_ref_sys OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 56840)
-- Name: grid_ref_sys_id_seq; Type: SEQUENCE; Schema: bdc; Owner: postgres
--

CREATE SEQUENCE bdc.grid_ref_sys_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bdc.grid_ref_sys_id_seq OWNER TO postgres;

--
-- TOC entry 5607 (class 0 OID 0)
-- Dependencies: 225
-- Name: grid_ref_sys_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.grid_ref_sys_id_seq OWNED BY bdc.grid_ref_sys.id;


--
-- TOC entry 226 (class 1259 OID 56842)
-- Name: items; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.items (
    id integer NOT NULL,
    name character varying NOT NULL,
    collection_id integer NOT NULL,
    tile_id integer,
    start_date timestamp with time zone NOT NULL,
    end_date timestamp with time zone NOT NULL,
    cloud_cover numeric,
    assets jsonb,
    metadata jsonb,
    provider_id integer,
    application_id integer,
    geom public.geometry(Polygon,4326),
    min_convex_hull public.geometry(Polygon,4326),
    srid integer,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.items OWNER TO postgres;

--
-- TOC entry 5608 (class 0 OID 0)
-- Dependencies: 226
-- Name: COLUMN items.assets; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.items.assets IS 'Follow the JSONSchema @jsonschemas/item-assets.json';


--
-- TOC entry 5609 (class 0 OID 0)
-- Dependencies: 226
-- Name: COLUMN items.metadata; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.items.metadata IS 'Follow the JSONSchema @jsonschemas/item-metadata.json';


--
-- TOC entry 227 (class 1259 OID 56850)
-- Name: items_id_seq; Type: SEQUENCE; Schema: bdc; Owner: postgres
--

CREATE SEQUENCE bdc.items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bdc.items_id_seq OWNER TO postgres;

--
-- TOC entry 5610 (class 0 OID 0)
-- Dependencies: 227
-- Name: items_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.items_id_seq OWNED BY bdc.items.id;


--
-- TOC entry 228 (class 1259 OID 56852)
-- Name: mime_type; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.mime_type (
    id integer NOT NULL,
    name text NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.mime_type OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 56860)
-- Name: mime_type_id_seq; Type: SEQUENCE; Schema: bdc; Owner: postgres
--

CREATE SEQUENCE bdc.mime_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bdc.mime_type_id_seq OWNER TO postgres;

--
-- TOC entry 5611 (class 0 OID 0)
-- Dependencies: 229
-- Name: mime_type_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.mime_type_id_seq OWNED BY bdc.mime_type.id;


--
-- TOC entry 230 (class 1259 OID 56862)
-- Name: providers; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.providers (
    id integer NOT NULL,
    name character varying(64),
    description text,
    uri character varying(255),
    credentials jsonb,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.providers OWNER TO postgres;

--
-- TOC entry 5612 (class 0 OID 0)
-- Dependencies: 230
-- Name: COLUMN providers.credentials; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.providers.credentials IS 'Follow the JSONSchema @jsonschemas/provider-credentials.json';


--
-- TOC entry 231 (class 1259 OID 56870)
-- Name: providers_id_seq; Type: SEQUENCE; Schema: bdc; Owner: postgres
--

CREATE SEQUENCE bdc.providers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bdc.providers_id_seq OWNER TO postgres;

--
-- TOC entry 5613 (class 0 OID 0)
-- Dependencies: 231
-- Name: providers_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.providers_id_seq OWNED BY bdc.providers.id;


--
-- TOC entry 232 (class 1259 OID 56872)
-- Name: quicklook; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.quicklook (
    collection_id integer NOT NULL,
    red integer,
    green integer,
    blue integer,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.quicklook OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 56877)
-- Name: resolution_unit; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.resolution_unit (
    id integer NOT NULL,
    name character varying(20) NOT NULL,
    symbol character varying(3),
    description text,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.resolution_unit OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 56885)
-- Name: resolution_unit_id_seq; Type: SEQUENCE; Schema: bdc; Owner: postgres
--

CREATE SEQUENCE bdc.resolution_unit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bdc.resolution_unit_id_seq OWNER TO postgres;

--
-- TOC entry 5614 (class 0 OID 0)
-- Dependencies: 234
-- Name: resolution_unit_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.resolution_unit_id_seq OWNED BY bdc.resolution_unit.id;


--
-- TOC entry 235 (class 1259 OID 56887)
-- Name: tiles; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.tiles (
    id integer NOT NULL,
    grid_ref_sys_id integer NOT NULL,
    name character varying(20) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.tiles OWNER TO postgres;

--
-- TOC entry 236 (class 1259 OID 56892)
-- Name: tiles_id_seq; Type: SEQUENCE; Schema: bdc; Owner: postgres
--

CREATE SEQUENCE bdc.tiles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bdc.tiles_id_seq OWNER TO postgres;

--
-- TOC entry 5615 (class 0 OID 0)
-- Dependencies: 236
-- Name: tiles_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.tiles_id_seq OWNED BY bdc.tiles.id;


--
-- TOC entry 237 (class 1259 OID 56894)
-- Name: timeline; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.timeline (
    collection_id integer NOT NULL,
    time_inst timestamp with time zone NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE bdc.timeline OWNER TO postgres;

--
-- TOC entry 238 (class 1259 OID 56899)
-- Name: alembic_version; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.alembic_version (
    version_num character varying(32) NOT NULL
);


ALTER TABLE public.alembic_version OWNER TO postgres;

--
-- TOC entry 5299 (class 2604 OID 56902)
-- Name: applications id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.applications ALTER COLUMN id SET DEFAULT nextval('bdc.applications_id_seq'::regclass);


--
-- TOC entry 5304 (class 2604 OID 56903)
-- Name: bands id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.bands ALTER COLUMN id SET DEFAULT nextval('bdc.bands_id_seq'::regclass);


--
-- TOC entry 5312 (class 2604 OID 56904)
-- Name: collections id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections ALTER COLUMN id SET DEFAULT nextval('bdc.collections_id_seq'::regclass);


--
-- TOC entry 5317 (class 2604 OID 56905)
-- Name: composite_functions id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.composite_functions ALTER COLUMN id SET DEFAULT nextval('bdc.composite_functions_id_seq'::regclass);


--
-- TOC entry 5320 (class 2604 OID 56906)
-- Name: grid_ref_sys id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.grid_ref_sys ALTER COLUMN id SET DEFAULT nextval('bdc.grid_ref_sys_id_seq'::regclass);


--
-- TOC entry 5323 (class 2604 OID 56907)
-- Name: items id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.items ALTER COLUMN id SET DEFAULT nextval('bdc.items_id_seq'::regclass);


--
-- TOC entry 5326 (class 2604 OID 56908)
-- Name: mime_type id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.mime_type ALTER COLUMN id SET DEFAULT nextval('bdc.mime_type_id_seq'::regclass);


--
-- TOC entry 5329 (class 2604 OID 56909)
-- Name: providers id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.providers ALTER COLUMN id SET DEFAULT nextval('bdc.providers_id_seq'::regclass);


--
-- TOC entry 5334 (class 2604 OID 56910)
-- Name: resolution_unit id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.resolution_unit ALTER COLUMN id SET DEFAULT nextval('bdc.resolution_unit_id_seq'::regclass);


--
-- TOC entry 5337 (class 2604 OID 56911)
-- Name: tiles id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.tiles ALTER COLUMN id SET DEFAULT nextval('bdc.tiles_id_seq'::regclass);


--
-- TOC entry 5564 (class 0 OID 56774)
-- Dependencies: 213
-- Data for Name: applications; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5566 (class 0 OID 56784)
-- Dependencies: 215
-- Data for Name: band_src; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5567 (class 0 OID 56789)
-- Dependencies: 216
-- Data for Name: bands; Type: TABLE DATA; Schema: bdc; Owner: postgres
--

INSERT INTO bdc.bands VALUES (1, 'B1', 'blue', 'WPM - L2 - B1 - blue', 0.45, 0.52, NULL, NULL, 8, 8, NULL, NULL, 5, 1, NULL, NULL, '{"level": "L2", "sensor": "WPM"}', '2020-12-01 13:47:34.421827+00', '2020-12-01 13:47:34.421827+00');
INSERT INTO bdc.bands VALUES (2, 'B1', 'blue', 'WPM - L4 - B1 - blue', 0.45, 0.52, NULL, NULL, 8, 8, NULL, NULL, 6, 1, NULL, NULL, '{"level": "L4", "sensor": "WPM"}', '2020-12-01 13:47:34.42498+00', '2020-12-01 13:47:34.42498+00');
INSERT INTO bdc.bands VALUES (3, 'B2', 'green', 'WPM - L2 - B2 - green', 0.52, 0.59, NULL, NULL, 8, 8, NULL, NULL, 5, 1, NULL, NULL, '{"level": "L2", "sensor": "WPM"}', '2020-12-01 13:47:34.427069+00', '2020-12-01 13:47:34.427069+00');
INSERT INTO bdc.bands VALUES (4, 'B2', 'green', 'WPM - L4 - B2 - green', 0.52, 0.59, NULL, NULL, 8, 8, NULL, NULL, 6, 1, NULL, NULL, '{"level": "L4", "sensor": "WPM"}', '2020-12-01 13:47:34.42904+00', '2020-12-01 13:47:34.42904+00');
INSERT INTO bdc.bands VALUES (5, 'B3', 'red', 'WPM - L2 - B3 - red', 0.63, 0.69, NULL, NULL, 8, 8, NULL, NULL, 5, 1, NULL, NULL, '{"level": "L2", "sensor": "WPM"}', '2020-12-01 13:47:34.432787+00', '2020-12-01 13:47:34.432787+00');
INSERT INTO bdc.bands VALUES (6, 'B3', 'red', 'WPM - L4 - B3 - red', 0.63, 0.69, NULL, NULL, 8, 8, NULL, NULL, 6, 1, NULL, NULL, '{"level": "L4", "sensor": "WPM"}', '2020-12-01 13:47:34.434714+00', '2020-12-01 13:47:34.434714+00');
INSERT INTO bdc.bands VALUES (7, 'B4', 'nir', 'WPM - L2 - B4 - nir', 0.77, 0.89, NULL, NULL, 8, 8, NULL, NULL, 5, 1, NULL, NULL, '{"level": "L2", "sensor": "WPM"}', '2020-12-01 13:47:34.436711+00', '2020-12-01 13:47:34.436711+00');
INSERT INTO bdc.bands VALUES (8, 'B4', 'nir', 'WPM - L4 - B4 - nir', 0.77, 0.89, NULL, NULL, 8, 8, NULL, NULL, 6, 1, NULL, NULL, '{"level": "L4", "sensor": "WPM"}', '2020-12-01 13:47:34.438697+00', '2020-12-01 13:47:34.438697+00');
INSERT INTO bdc.bands VALUES (9, 'P', 'pan', 'WPM - L2 - P - pan', 0.45, 0.9, NULL, NULL, 2, 2, NULL, NULL, 5, 1, NULL, NULL, '{"level": "L2", "sensor": "WPM"}', '2020-12-01 13:47:34.44055+00', '2020-12-01 13:47:34.44055+00');
INSERT INTO bdc.bands VALUES (10, 'P', 'pan', 'WPM - L4 - P - pan', 0.45, 0.9, NULL, NULL, 2, 2, NULL, NULL, 6, 1, NULL, NULL, '{"level": "L4", "sensor": "WPM"}', '2020-12-01 13:47:34.44308+00', '2020-12-01 13:47:34.44308+00');
INSERT INTO bdc.bands VALUES (11, 'B05', 'blue', 'MUX - L2 - B05 - blue', 0.45, 0.52, NULL, NULL, 16.5, 16.5, NULL, NULL, 1, 1, NULL, NULL, '{"level": "L2", "sensor": "MUX"}', '2020-12-01 13:47:34.445139+00', '2020-12-01 13:47:34.445139+00');
INSERT INTO bdc.bands VALUES (12, 'B05', 'blue', 'MUX - L4 - B05 - blue', 0.45, 0.52, NULL, NULL, 16.5, 16.5, NULL, NULL, 2, 1, NULL, NULL, '{"level": "L4", "sensor": "MUX"}', '2020-12-01 13:47:34.447104+00', '2020-12-01 13:47:34.447104+00');
INSERT INTO bdc.bands VALUES (13, 'B06', 'green', 'MUX - L2 - B06 - green', 0.52, 0.59, NULL, NULL, 16.5, 16.5, NULL, NULL, 1, 1, NULL, NULL, '{"level": "L2", "sensor": "MUX"}', '2020-12-01 13:47:34.449031+00', '2020-12-01 13:47:34.449031+00');
INSERT INTO bdc.bands VALUES (14, 'B06', 'green', 'MUX - L4 - B06 - green', 0.52, 0.59, NULL, NULL, 16.5, 16.5, NULL, NULL, 2, 1, NULL, NULL, '{"level": "L4", "sensor": "MUX"}', '2020-12-01 13:47:34.451046+00', '2020-12-01 13:47:34.451046+00');
INSERT INTO bdc.bands VALUES (15, 'B07', 'red', 'MUX - L2 - B07 - red', 0.63, 0.69, NULL, NULL, 16.5, 16.5, NULL, NULL, 1, 1, NULL, NULL, '{"level": "L2", "sensor": "MUX"}', '2020-12-01 13:47:34.45301+00', '2020-12-01 13:47:34.45301+00');
INSERT INTO bdc.bands VALUES (16, 'B07', 'red', 'MUX - L4 - B07 - red', 0.63, 0.69, NULL, NULL, 16.5, 16.5, NULL, NULL, 2, 1, NULL, NULL, '{"level": "L4", "sensor": "MUX"}', '2020-12-01 13:47:34.45495+00', '2020-12-01 13:47:34.45495+00');
INSERT INTO bdc.bands VALUES (17, 'B08', 'nir', 'MUX - L2 - B08 - nir', 0.77, 0.89, NULL, NULL, 16.5, 16.5, NULL, NULL, 1, 1, NULL, NULL, '{"level": "L2", "sensor": "MUX"}', '2020-12-01 13:47:34.456878+00', '2020-12-01 13:47:34.456878+00');
INSERT INTO bdc.bands VALUES (18, 'B08', 'nir', 'MUX - L4 - B08 - nir', 0.77, 0.89, NULL, NULL, 16.5, 16.5, NULL, NULL, 2, 1, NULL, NULL, '{"level": "L4", "sensor": "MUX"}', '2020-12-01 13:47:34.458701+00', '2020-12-01 13:47:34.458701+00');
INSERT INTO bdc.bands VALUES (19, 'B13', 'blue', 'WFI - L2 - B13 - blue', 0.45, 0.52, NULL, NULL, 55, 55, NULL, NULL, 3, 1, NULL, NULL, '{"level": "L2", "sensor": "WFI"}', '2020-12-01 13:47:34.460584+00', '2020-12-01 13:47:34.460584+00');
INSERT INTO bdc.bands VALUES (20, 'B13', 'blue', 'WFI - L4 - B13 - blue', 0.45, 0.52, NULL, NULL, 55, 55, NULL, NULL, 4, 1, NULL, NULL, '{"level": "L4", "sensor": "WFI"}', '2020-12-01 13:47:34.462369+00', '2020-12-01 13:47:34.462369+00');
INSERT INTO bdc.bands VALUES (21, 'B14', 'green', 'WFI - L2 - B14 - green', 0.52, 0.59, NULL, NULL, 55, 55, NULL, NULL, 3, 1, NULL, NULL, '{"level": "L2", "sensor": "WFI"}', '2020-12-01 13:47:34.46419+00', '2020-12-01 13:47:34.46419+00');
INSERT INTO bdc.bands VALUES (22, 'B14', 'green', 'WFI - L4 - B14 - green', 0.52, 0.59, NULL, NULL, 55, 55, NULL, NULL, 4, 1, NULL, NULL, '{"level": "L4", "sensor": "WFI"}', '2020-12-01 13:47:34.466121+00', '2020-12-01 13:47:34.466121+00');
INSERT INTO bdc.bands VALUES (23, 'B15', 'red', 'WFI - L2 - B15 - red', 0.63, 0.69, NULL, NULL, 55, 55, NULL, NULL, 3, 1, NULL, NULL, '{"level": "L2", "sensor": "WFI"}', '2020-12-01 13:47:34.468061+00', '2020-12-01 13:47:34.468061+00');
INSERT INTO bdc.bands VALUES (24, 'B15', 'red', 'WFI - L4 - B15 - red', 0.63, 0.69, NULL, NULL, 55, 55, NULL, NULL, 4, 1, NULL, NULL, '{"level": "L4", "sensor": "WFI"}', '2020-12-01 13:47:34.469954+00', '2020-12-01 13:47:34.469954+00');
INSERT INTO bdc.bands VALUES (25, 'B16', 'nir', 'WFI - L2 - B16 - nir', 0.77, 0.89, NULL, NULL, 55, 55, NULL, NULL, 3, 1, NULL, NULL, '{"level": "L2", "sensor": "WFI"}', '2020-12-01 13:47:34.471863+00', '2020-12-01 13:47:34.471863+00');
INSERT INTO bdc.bands VALUES (26, 'B16', 'nir', 'WFI - L4 - B16 - nir', 0.77, 0.89, NULL, NULL, 55, 55, NULL, NULL, 4, 1, NULL, NULL, '{"level": "L4", "sensor": "WFI"}', '2020-12-01 13:47:34.473635+00', '2020-12-01 13:47:34.473635+00');


--
-- TOC entry 5569 (class 0 OID 56799)
-- Dependencies: 218
-- Data for Name: collection_src; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5570 (class 0 OID 56804)
-- Dependencies: 219
-- Data for Name: collections; Type: TABLE DATA; Schema: bdc; Owner: postgres
--

INSERT INTO bdc.collections VALUES (1, 'CBERS4A_MUX_L2_DN', 'CBERS4A_MUX_L2_DN', 'CBERS4A MUX Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (2, 'CBERS4A_MUX_L2_SR', 'CBERS4A_MUX_L2_SR', 'CBERS4A MUX Level2 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (3, 'CBERS4A_MUX_L4_DN', 'CBERS4A_MUX_L4_DN', 'CBERS4A MUX Level4 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:58:39+00', '2020-11-27 14:20:24+00', '0103000020E6100000010000000500000035EF3845474E53C0545227A0892042C035EF3845474E53C07D3F355EBAD942407C61325530C244407D3F355EBAD942407C61325530C24440545227A0892042C035EF3845474E53C0545227A0892042C0', 1, NULL, NULL, '2020-12-01 13:47:34.413328+00', '2020-12-01 13:47:34.413328+00');
INSERT INTO bdc.collections VALUES (4, 'CBERS4A_MUX_L4_SR', 'CBERS4A_MUX_L4_SR', 'CBERS4A MUX Level4 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:58:39+00', '2020-11-27 14:20:24+00', '0103000020E6100000010000000500000035EF3845474E53C0545227A0892042C035EF3845474E53C07D3F355EBAD942407C61325530C244407D3F355EBAD942407C61325530C24440545227A0892042C035EF3845474E53C0545227A0892042C0', 1, NULL, NULL, '2020-12-01 13:47:34.413328+00', '2020-12-01 13:47:34.413328+00');
INSERT INTO bdc.collections VALUES (5, 'CBERS4A_WFI_L2_DN', 'CBERS4A_WFI_L2_DN', 'CBERS4A WFI Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:56:15+00', '2020-11-27 14:14:59+00', '0103000020E61000000100000005000000D656EC2FBBD354C00F9C33A2B4974FC0D656EC2FBBD354C0E09C11A5BDC55140D34D6210584D6240E09C11A5BDC55140D34D6210584D62400F9C33A2B4974FC0D656EC2FBBD354C00F9C33A2B4974FC0', 1, NULL, NULL, '2020-12-01 13:47:34.414378+00', '2020-12-01 13:47:34.414378+00');
INSERT INTO bdc.collections VALUES (6, 'CBERS4A_WFI_L2_SR', 'CBERS4A_WFI_L2_SR', 'CBERS4A WFI Level2 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:56:15+00', '2020-11-27 14:14:59+00', '0103000020E61000000100000005000000D656EC2FBBD354C00F9C33A2B4974FC0D656EC2FBBD354C0E09C11A5BDC55140D34D6210584D6240E09C11A5BDC55140D34D6210584D62400F9C33A2B4974FC0D656EC2FBBD354C00F9C33A2B4974FC0', 1, NULL, NULL, '2020-12-01 13:47:34.414378+00', '2020-12-01 13:47:34.414378+00');
INSERT INTO bdc.collections VALUES (7, 'CBERS4A_WFI_L4_DN', 'CBERS4A_WFI_L4_DN', 'CBERS4A WFI Level4 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:59:42+00', '2020-11-27 14:20:09+00', '0103000020E61000000100000005000000F163CC5D4BC453C024287E8CB91343C0F163CC5D4BC453C063EE5A423E383B4014AE47E17A44454063EE5A423E383B4014AE47E17A44454024287E8CB91343C0F163CC5D4BC453C024287E8CB91343C0', 1, NULL, NULL, '2020-12-01 13:47:34.415317+00', '2020-12-01 13:47:34.415317+00');
INSERT INTO bdc.collections VALUES (8, 'CBERS4A_WFI_L4_SR', 'CBERS4A_WFI_L4_SR', 'CBERS4A WFI Level4 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:59:42+00', '2020-11-27 14:20:09+00', '0103000020E61000000100000005000000F163CC5D4BC453C024287E8CB91343C0F163CC5D4BC453C063EE5A423E383B4014AE47E17A44454063EE5A423E383B4014AE47E17A44454024287E8CB91343C0F163CC5D4BC453C024287E8CB91343C0', 1, NULL, NULL, '2020-12-01 13:47:34.415317+00', '2020-12-01 13:47:34.415317+00');
INSERT INTO bdc.collections VALUES (9, 'CBERS4A_WPM_L2_DN', 'CBERS4A_WPM_L2_DN', 'CBERS4A WPM Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:49+00', '2020-11-27 14:10:14+00', '0103000020E61000000100000005000000EC2FBB270F6755C0280F0BB5A6E142C0EC2FBB270F6755C07D3F355EBA3D52407D3F355EBAE961407D3F355EBA3D52407D3F355EBAE96140280F0BB5A6E142C0EC2FBB270F6755C0280F0BB5A6E142C0', 1, NULL, NULL, '2020-12-01 13:47:34.416189+00', '2020-12-01 13:47:34.416189+00');
INSERT INTO bdc.collections VALUES (10, 'CBERS4A_WPM_L2_SR', 'CBERS4A_WPM_L2_SR', 'CBERS4A WPM Level2 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:49+00', '2020-11-27 14:10:14+00', '0103000020E61000000100000005000000EC2FBB270F6755C0280F0BB5A6E142C0EC2FBB270F6755C07D3F355EBA3D52407D3F355EBAE961407D3F355EBA3D52407D3F355EBAE96140280F0BB5A6E142C0EC2FBB270F6755C0280F0BB5A6E142C0', 1, NULL, NULL, '2020-12-01 13:47:34.416189+00', '2020-12-01 13:47:34.416189+00');
INSERT INTO bdc.collections VALUES (11, 'CBERS4A_WPM_L4_DN', 'CBERS4A_WPM_L4_DN', 'CBERS4A WPM Level4 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:58:50+00', '2020-11-26 15:33:23+00', '0103000020E61000000100000005000000B84082E2C74C53C0956588635D7C42C0B84082E2C74C53C0401878EE3D9C1E40713D0AD7A3A841C0401878EE3D9C1E40713D0AD7A3A841C0956588635D7C42C0B84082E2C74C53C0956588635D7C42C0', 1, NULL, NULL, '2020-12-01 13:47:34.417071+00', '2020-12-01 13:47:34.417071+00');
INSERT INTO bdc.collections VALUES (12, 'CBERS4A_WPM_L4_SR', 'CBERS4A_WPM_L4_SR', 'CBERS4A WPM Level4 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:58:50+00', '2020-11-26 15:33:23+00', '0103000020E61000000100000005000000B84082E2C74C53C0956588635D7C42C0B84082E2C74C53C0401878EE3D9C1E40713D0AD7A3A841C0401878EE3D9C1E40713D0AD7A3A841C0956588635D7C42C0B84082E2C74C53C0956588635D7C42C0', 1, NULL, NULL, '2020-12-01 13:47:34.417071+00', '2020-12-01 13:47:34.417071+00');
INSERT INTO bdc.collections VALUES (13, 'CBERS2B_CCD_L2_DN', 'CBERS2B_CCD_L2_DN', 'CBERS2B CCD Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:58:50+00', '2020-11-26 15:33:23+00', '0103000020E61000000100000005000000B84082E2C74C53C0956588635D7C42C0B84082E2C74C53C0401878EE3D9C1E40713D0AD7A3A841C0401878EE3D9C1E40713D0AD7A3A841C0956588635D7C42C0B84082E2C74C53C0956588635D7C42C0', 1, NULL, NULL, '2020-12-01 13:47:34.417071+00', '2020-12-01 13:47:34.417071+00');
INSERT INTO bdc.collections VALUES (14, 'CBERS2B_HRC_L2_DN', 'CBERS2B_HRC_L2_DN', 'CBERS2B HRC Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:58:50+00', '2020-11-26 15:33:23+00', '0103000020E61000000100000005000000B84082E2C74C53C0956588635D7C42C0B84082E2C74C53C0401878EE3D9C1E40713D0AD7A3A841C0401878EE3D9C1E40713D0AD7A3A841C0956588635D7C42C0B84082E2C74C53C0956588635D7C42C0', 1, NULL, NULL, '2020-12-01 13:47:34.417071+00', '2020-12-01 13:47:34.417071+00');
INSERT INTO bdc.collections VALUES (15, 'CBERS2B_WFI_L2_DN', 'CBERS2B_WFI_L2_DN', 'CBERS2B WFI Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:58:50+00', '2020-11-26 15:33:23+00', '0103000020E61000000100000005000000B84082E2C74C53C0956588635D7C42C0B84082E2C74C53C0401878EE3D9C1E40713D0AD7A3A841C0401878EE3D9C1E40713D0AD7A3A841C0956588635D7C42C0B84082E2C74C53C0956588635D7C42C0', 1, NULL, NULL, '2020-12-01 13:47:34.417071+00', '2020-12-01 13:47:34.417071+00');


--
-- TOC entry 5572 (class 0 OID 56817)
-- Dependencies: 221
-- Data for Name: collections_providers; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5573 (class 0 OID 56822)
-- Dependencies: 222
-- Data for Name: composite_functions; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5575 (class 0 OID 56832)
-- Dependencies: 224
-- Data for Name: grid_ref_sys; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5577 (class 0 OID 56842)
-- Dependencies: 226
-- Data for Name: items; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5579 (class 0 OID 56852)
-- Dependencies: 228
-- Data for Name: mime_type; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5581 (class 0 OID 56862)
-- Dependencies: 230
-- Data for Name: providers; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5583 (class 0 OID 56872)
-- Dependencies: 232
-- Data for Name: quicklook; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5584 (class 0 OID 56877)
-- Dependencies: 233
-- Data for Name: resolution_unit; Type: TABLE DATA; Schema: bdc; Owner: postgres
--

INSERT INTO bdc.resolution_unit VALUES (1, 'micrometre', 'μm', NULL, '2020-12-01 13:47:34.418444+00', '2020-12-01 13:47:34.418444+00');


--
-- TOC entry 5586 (class 0 OID 56887)
-- Dependencies: 235
-- Data for Name: tiles; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5588 (class 0 OID 56894)
-- Dependencies: 237
-- Data for Name: timeline; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5589 (class 0 OID 56899)
-- Dependencies: 238
-- Data for Name: alembic_version; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.alembic_version VALUES ('be5ae740887a');


--
-- TOC entry 5295 (class 0 OID 55479)
-- Dependencies: 199
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- TOC entry 5616 (class 0 OID 0)
-- Dependencies: 214
-- Name: applications_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.applications_id_seq', 1, false);


--
-- TOC entry 5617 (class 0 OID 0)
-- Dependencies: 217
-- Name: bands_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.bands_id_seq', 1, false);


--
-- TOC entry 5618 (class 0 OID 0)
-- Dependencies: 220
-- Name: collections_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.collections_id_seq', 1, false);


--
-- TOC entry 5619 (class 0 OID 0)
-- Dependencies: 223
-- Name: composite_functions_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.composite_functions_id_seq', 1, false);


--
-- TOC entry 5620 (class 0 OID 0)
-- Dependencies: 225
-- Name: grid_ref_sys_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.grid_ref_sys_id_seq', 1, false);


--
-- TOC entry 5621 (class 0 OID 0)
-- Dependencies: 227
-- Name: items_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.items_id_seq', 51240, true);


--
-- TOC entry 5622 (class 0 OID 0)
-- Dependencies: 229
-- Name: mime_type_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.mime_type_id_seq', 1, false);


--
-- TOC entry 5623 (class 0 OID 0)
-- Dependencies: 231
-- Name: providers_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.providers_id_seq', 1, false);


--
-- TOC entry 5624 (class 0 OID 0)
-- Dependencies: 234
-- Name: resolution_unit_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.resolution_unit_id_seq', 1, false);


--
-- TOC entry 5625 (class 0 OID 0)
-- Dependencies: 236
-- Name: tiles_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.tiles_id_seq', 1, false);


--
-- TOC entry 5343 (class 2606 OID 56913)
-- Name: applications applications_name_key; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.applications
    ADD CONSTRAINT applications_name_key UNIQUE (name, version);


--
-- TOC entry 5345 (class 2606 OID 56915)
-- Name: applications applications_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.applications
    ADD CONSTRAINT applications_pkey PRIMARY KEY (id);


--
-- TOC entry 5347 (class 2606 OID 56917)
-- Name: band_src band_src_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.band_src
    ADD CONSTRAINT band_src_pkey PRIMARY KEY (band_id, band_src_id);


--
-- TOC entry 5349 (class 2606 OID 56919)
-- Name: bands bands_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.bands
    ADD CONSTRAINT bands_pkey PRIMARY KEY (id);


--
-- TOC entry 5355 (class 2606 OID 56921)
-- Name: collection_src collection_src_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collection_src
    ADD CONSTRAINT collection_src_pkey PRIMARY KEY (collection_id, collection_src_id);


--
-- TOC entry 5357 (class 2606 OID 56923)
-- Name: collections collections_name_key; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections
    ADD CONSTRAINT collections_name_key UNIQUE (name, version);


--
-- TOC entry 5359 (class 2606 OID 56925)
-- Name: collections collections_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections
    ADD CONSTRAINT collections_pkey PRIMARY KEY (id);


--
-- TOC entry 5364 (class 2606 OID 56927)
-- Name: collections_providers collections_providers_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections_providers
    ADD CONSTRAINT collections_providers_pkey PRIMARY KEY (provider_id, collection_id);


--
-- TOC entry 5366 (class 2606 OID 56929)
-- Name: composite_functions composite_functions_alias_key; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.composite_functions
    ADD CONSTRAINT composite_functions_alias_key UNIQUE (alias);


--
-- TOC entry 5368 (class 2606 OID 56931)
-- Name: composite_functions composite_functions_name_key; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.composite_functions
    ADD CONSTRAINT composite_functions_name_key UNIQUE (name);


--
-- TOC entry 5370 (class 2606 OID 56933)
-- Name: composite_functions composite_functions_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.composite_functions
    ADD CONSTRAINT composite_functions_pkey PRIMARY KEY (id);


--
-- TOC entry 5372 (class 2606 OID 56935)
-- Name: grid_ref_sys grid_ref_sys_name_key; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.grid_ref_sys
    ADD CONSTRAINT grid_ref_sys_name_key UNIQUE (name);


--
-- TOC entry 5374 (class 2606 OID 56937)
-- Name: grid_ref_sys grid_ref_sys_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.grid_ref_sys
    ADD CONSTRAINT grid_ref_sys_pkey PRIMARY KEY (id);


--
-- TOC entry 5385 (class 2606 OID 56939)
-- Name: items items_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.items
    ADD CONSTRAINT items_pkey PRIMARY KEY (id);


--
-- TOC entry 5387 (class 2606 OID 56941)
-- Name: mime_type mime_type_name_key; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.mime_type
    ADD CONSTRAINT mime_type_name_key UNIQUE (name);


--
-- TOC entry 5389 (class 2606 OID 56943)
-- Name: mime_type mime_type_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.mime_type
    ADD CONSTRAINT mime_type_pkey PRIMARY KEY (id);


--
-- TOC entry 5392 (class 2606 OID 56945)
-- Name: providers providers_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.providers
    ADD CONSTRAINT providers_pkey PRIMARY KEY (id);


--
-- TOC entry 5394 (class 2606 OID 56947)
-- Name: quicklook quicklook_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.quicklook
    ADD CONSTRAINT quicklook_pkey PRIMARY KEY (collection_id);


--
-- TOC entry 5396 (class 2606 OID 56949)
-- Name: resolution_unit resolution_unit_name_key; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.resolution_unit
    ADD CONSTRAINT resolution_unit_name_key UNIQUE (name);


--
-- TOC entry 5398 (class 2606 OID 56951)
-- Name: resolution_unit resolution_unit_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.resolution_unit
    ADD CONSTRAINT resolution_unit_pkey PRIMARY KEY (id);


--
-- TOC entry 5403 (class 2606 OID 56953)
-- Name: tiles tiles_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.tiles
    ADD CONSTRAINT tiles_pkey PRIMARY KEY (id);


--
-- TOC entry 5406 (class 2606 OID 56955)
-- Name: timeline timeline_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.timeline
    ADD CONSTRAINT timeline_pkey PRIMARY KEY (collection_id, time_inst);


--
-- TOC entry 5408 (class 2606 OID 56957)
-- Name: alembic_version alembic_version_pkc; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alembic_version
    ADD CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num);


--
-- TOC entry 5350 (class 1259 OID 56958)
-- Name: idx_bdc_bands_collection_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_bands_collection_id ON bdc.bands USING btree (collection_id);


--
-- TOC entry 5351 (class 1259 OID 56959)
-- Name: idx_bdc_bands_common_name; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_bands_common_name ON bdc.bands USING btree (common_name);


--
-- TOC entry 5352 (class 1259 OID 56960)
-- Name: idx_bdc_bands_mime_type_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_bands_mime_type_id ON bdc.bands USING btree (mime_type_id);


--
-- TOC entry 5353 (class 1259 OID 56961)
-- Name: idx_bdc_bands_name; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_bands_name ON bdc.bands USING btree (name);


--
-- TOC entry 5360 (class 1259 OID 56962)
-- Name: idx_bdc_collections_extent; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_collections_extent ON bdc.collections USING gist (extent);


--
-- TOC entry 5361 (class 1259 OID 56963)
-- Name: idx_bdc_collections_grid_ref_sys_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_collections_grid_ref_sys_id ON bdc.collections USING btree (grid_ref_sys_id);


--
-- TOC entry 5362 (class 1259 OID 56964)
-- Name: idx_bdc_collections_name; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_collections_name ON bdc.collections USING btree (name);


--
-- TOC entry 5375 (class 1259 OID 56965)
-- Name: idx_bdc_items_cloud_cover; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_cloud_cover ON bdc.items USING btree (cloud_cover);


--
-- TOC entry 5376 (class 1259 OID 56966)
-- Name: idx_bdc_items_collection_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_collection_id ON bdc.items USING btree (collection_id);


--
-- TOC entry 5377 (class 1259 OID 56967)
-- Name: idx_bdc_items_geom; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_geom ON bdc.items USING gist (geom);


--
-- TOC entry 5378 (class 1259 OID 56968)
-- Name: idx_bdc_items_min_convex_hull; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_min_convex_hull ON bdc.items USING gist (min_convex_hull);


--
-- TOC entry 5379 (class 1259 OID 56969)
-- Name: idx_bdc_items_name; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_name ON bdc.items USING btree (name);


--
-- TOC entry 5380 (class 1259 OID 56970)
-- Name: idx_bdc_items_provider_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_provider_id ON bdc.items USING btree (provider_id);


--
-- TOC entry 5381 (class 1259 OID 56971)
-- Name: idx_bdc_items_start_date; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_start_date ON bdc.items USING btree (start_date DESC);


--
-- TOC entry 5382 (class 1259 OID 56972)
-- Name: idx_bdc_items_tile_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_tile_id ON bdc.items USING btree (tile_id);


--
-- TOC entry 5390 (class 1259 OID 56973)
-- Name: idx_bdc_providers_name; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_providers_name ON bdc.providers USING btree (name);


--
-- TOC entry 5399 (class 1259 OID 56974)
-- Name: idx_bdc_tiles_grid_ref_sys_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_tiles_grid_ref_sys_id ON bdc.tiles USING btree (grid_ref_sys_id);


--
-- TOC entry 5400 (class 1259 OID 56975)
-- Name: idx_bdc_tiles_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_tiles_id ON bdc.tiles USING btree (id);


--
-- TOC entry 5401 (class 1259 OID 56976)
-- Name: idx_bdc_tiles_name; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_tiles_name ON bdc.tiles USING btree (name);


--
-- TOC entry 5404 (class 1259 OID 56977)
-- Name: idx_bdc_timeline_collection_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_timeline_collection_id ON bdc.timeline USING btree (collection_id, time_inst DESC);


--
-- TOC entry 5383 (class 1259 OID 56978)
-- Name: idx_items_start_date_end_date; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_items_start_date_end_date ON bdc.items USING btree (start_date, end_date);


--
-- TOC entry 5433 (class 2620 OID 56979)
-- Name: bands check_bands_metadata_index_trigger; Type: TRIGGER; Schema: bdc; Owner: postgres
--

CREATE TRIGGER check_bands_metadata_index_trigger AFTER INSERT OR UPDATE ON bdc.bands FOR EACH ROW EXECUTE PROCEDURE public.check_bands_metadata_index();


--
-- TOC entry 5434 (class 2620 OID 56980)
-- Name: items update_collection_time_trigger; Type: TRIGGER; Schema: bdc; Owner: postgres
--

CREATE TRIGGER update_collection_time_trigger AFTER INSERT OR UPDATE ON bdc.items FOR EACH ROW EXECUTE PROCEDURE public.update_collection_time();


--
-- TOC entry 5435 (class 2620 OID 56981)
-- Name: items update_update_timeline_trigger; Type: TRIGGER; Schema: bdc; Owner: postgres
--

CREATE TRIGGER update_update_timeline_trigger AFTER INSERT OR UPDATE ON bdc.items FOR EACH ROW EXECUTE PROCEDURE public.update_timeline();


--
-- TOC entry 5409 (class 2606 OID 56982)
-- Name: band_src band_src_band_id_bands_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.band_src
    ADD CONSTRAINT band_src_band_id_bands_fkey FOREIGN KEY (band_id) REFERENCES bdc.bands(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5410 (class 2606 OID 56987)
-- Name: band_src band_src_band_src_id_bands_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.band_src
    ADD CONSTRAINT band_src_band_src_id_bands_fkey FOREIGN KEY (band_src_id) REFERENCES bdc.bands(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5411 (class 2606 OID 56992)
-- Name: bands bands_collection_id_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.bands
    ADD CONSTRAINT bands_collection_id_collections_fkey FOREIGN KEY (collection_id) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5412 (class 2606 OID 56997)
-- Name: bands bands_mime_type_id_mime_type_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.bands
    ADD CONSTRAINT bands_mime_type_id_mime_type_fkey FOREIGN KEY (mime_type_id) REFERENCES bdc.mime_type(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5413 (class 2606 OID 57002)
-- Name: bands bands_resolution_unit_id_resolution_unit_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.bands
    ADD CONSTRAINT bands_resolution_unit_id_resolution_unit_fkey FOREIGN KEY (resolution_unit_id) REFERENCES bdc.resolution_unit(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5414 (class 2606 OID 57007)
-- Name: collection_src collection_src_collection_id_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collection_src
    ADD CONSTRAINT collection_src_collection_id_collections_fkey FOREIGN KEY (collection_id) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5415 (class 2606 OID 57012)
-- Name: collection_src collection_src_collection_src_id_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collection_src
    ADD CONSTRAINT collection_src_collection_src_id_collections_fkey FOREIGN KEY (collection_src_id) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5416 (class 2606 OID 57017)
-- Name: collections collections_composite_function_id_composite_functions_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections
    ADD CONSTRAINT collections_composite_function_id_composite_functions_fkey FOREIGN KEY (composite_function_id) REFERENCES bdc.composite_functions(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5417 (class 2606 OID 57022)
-- Name: collections collections_grid_ref_sys_id_grid_ref_sys_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections
    ADD CONSTRAINT collections_grid_ref_sys_id_grid_ref_sys_fkey FOREIGN KEY (grid_ref_sys_id) REFERENCES bdc.grid_ref_sys(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5420 (class 2606 OID 57027)
-- Name: collections_providers collections_providers_collection_id_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections_providers
    ADD CONSTRAINT collections_providers_collection_id_collections_fkey FOREIGN KEY (collection_id) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5421 (class 2606 OID 57032)
-- Name: collections_providers collections_providers_provider_id_providers_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections_providers
    ADD CONSTRAINT collections_providers_provider_id_providers_fkey FOREIGN KEY (provider_id) REFERENCES bdc.providers(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5418 (class 2606 OID 57037)
-- Name: collections collections_version_predecessor_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections
    ADD CONSTRAINT collections_version_predecessor_collections_fkey FOREIGN KEY (version_predecessor) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5419 (class 2606 OID 57042)
-- Name: collections collections_version_successor_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections
    ADD CONSTRAINT collections_version_successor_collections_fkey FOREIGN KEY (version_successor) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5422 (class 2606 OID 57047)
-- Name: items items_application_id_applications_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.items
    ADD CONSTRAINT items_application_id_applications_fkey FOREIGN KEY (application_id) REFERENCES bdc.applications(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5423 (class 2606 OID 57052)
-- Name: items items_collection_id_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.items
    ADD CONSTRAINT items_collection_id_collections_fkey FOREIGN KEY (collection_id) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5424 (class 2606 OID 57057)
-- Name: items items_provider_id_providers_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.items
    ADD CONSTRAINT items_provider_id_providers_fkey FOREIGN KEY (provider_id) REFERENCES bdc.providers(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5425 (class 2606 OID 57062)
-- Name: items items_srid_spatial_ref_sys_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.items
    ADD CONSTRAINT items_srid_spatial_ref_sys_fkey FOREIGN KEY (srid) REFERENCES public.spatial_ref_sys(srid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5426 (class 2606 OID 57067)
-- Name: items items_tile_id_tiles_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.items
    ADD CONSTRAINT items_tile_id_tiles_fkey FOREIGN KEY (tile_id) REFERENCES bdc.tiles(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5427 (class 2606 OID 57072)
-- Name: quicklook quicklook_blue_bands_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.quicklook
    ADD CONSTRAINT quicklook_blue_bands_fkey FOREIGN KEY (blue) REFERENCES bdc.bands(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5428 (class 2606 OID 57077)
-- Name: quicklook quicklook_collection_id_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.quicklook
    ADD CONSTRAINT quicklook_collection_id_collections_fkey FOREIGN KEY (collection_id) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5429 (class 2606 OID 57082)
-- Name: quicklook quicklook_green_bands_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.quicklook
    ADD CONSTRAINT quicklook_green_bands_fkey FOREIGN KEY (green) REFERENCES bdc.bands(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5430 (class 2606 OID 57087)
-- Name: quicklook quicklook_red_bands_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.quicklook
    ADD CONSTRAINT quicklook_red_bands_fkey FOREIGN KEY (red) REFERENCES bdc.bands(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5431 (class 2606 OID 57092)
-- Name: tiles tiles_grid_ref_sys_id_grid_ref_sys_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.tiles
    ADD CONSTRAINT tiles_grid_ref_sys_id_grid_ref_sys_fkey FOREIGN KEY (grid_ref_sys_id) REFERENCES bdc.grid_ref_sys(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5432 (class 2606 OID 57097)
-- Name: timeline timeline_collection_id_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.timeline
    ADD CONSTRAINT timeline_collection_id_collections_fkey FOREIGN KEY (collection_id) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


-- Completed on 2021-02-01 19:16:30 UTC

--
-- PostgreSQL database dump complete
--

