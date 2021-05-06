--
-- PostgreSQL database dump
--

-- Dumped from database version 11.7 (Debian 11.7-2.pgdg100+1)
-- Dumped by pg_dump version 12.0

-- Started on 2021-05-06 17:18:00 UTC

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
-- TOC entry 9 (class 2615 OID 2832304)
-- Name: bdc; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA bdc;


ALTER SCHEMA bdc OWNER TO postgres;

--
-- TOC entry 2 (class 3079 OID 2832305)
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- TOC entry 5603 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions';


--
-- TOC entry 1922 (class 1247 OID 2833884)
-- Name: collection_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.collection_type AS ENUM (
    'cube',
    'collection'
);


ALTER TYPE public.collection_type OWNER TO postgres;

--
-- TOC entry 1925 (class 1247 OID 2833890)
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
-- TOC entry 1469 (class 1255 OID 2833907)
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
-- TOC entry 1470 (class 1255 OID 2833908)
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
-- TOC entry 1471 (class 1255 OID 2833909)
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
-- TOC entry 213 (class 1259 OID 2833910)
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
-- TOC entry 5604 (class 0 OID 0)
-- Dependencies: 213
-- Name: COLUMN applications.metadata; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.applications.metadata IS 'Follow the JSONSchema @jsonschemas/application-metadata.json';


--
-- TOC entry 214 (class 1259 OID 2833918)
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
-- TOC entry 5605 (class 0 OID 0)
-- Dependencies: 214
-- Name: applications_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.applications_id_seq OWNED BY bdc.applications.id;


--
-- TOC entry 215 (class 1259 OID 2833920)
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
-- TOC entry 216 (class 1259 OID 2833925)
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
-- TOC entry 5606 (class 0 OID 0)
-- Dependencies: 216
-- Name: COLUMN bands.metadata; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.bands.metadata IS 'Follow the JSONSchema @jsonschemas/band-metadata.json';


--
-- TOC entry 217 (class 1259 OID 2833933)
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
-- TOC entry 5607 (class 0 OID 0)
-- Dependencies: 217
-- Name: bands_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.bands_id_seq OWNED BY bdc.bands.id;


--
-- TOC entry 218 (class 1259 OID 2833935)
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
-- TOC entry 219 (class 1259 OID 2833940)
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
-- TOC entry 5608 (class 0 OID 0)
-- Dependencies: 219
-- Name: COLUMN collections.name; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.collections.name IS 'Collection name internally.';


--
-- TOC entry 5609 (class 0 OID 0)
-- Dependencies: 219
-- Name: COLUMN collections.title; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.collections.title IS 'A human-readable string naming for collection.';


--
-- TOC entry 5610 (class 0 OID 0)
-- Dependencies: 219
-- Name: COLUMN collections.temporal_composition_schema; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.collections.temporal_composition_schema IS 'Follow the JSONSchema @jsonschemas/collection-temporal-composition-schema.json';


--
-- TOC entry 5611 (class 0 OID 0)
-- Dependencies: 219
-- Name: COLUMN collections.composite_function_id; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.collections.composite_function_id IS 'Function schema identifier. Used for data cubes.';


--
-- TOC entry 5612 (class 0 OID 0)
-- Dependencies: 219
-- Name: COLUMN collections.metadata; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.collections.metadata IS 'Follow the JSONSchema @jsonschemas/collection-metadata.json';


--
-- TOC entry 220 (class 1259 OID 2833951)
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
-- TOC entry 5613 (class 0 OID 0)
-- Dependencies: 220
-- Name: collections_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.collections_id_seq OWNED BY bdc.collections.id;


--
-- TOC entry 221 (class 1259 OID 2833953)
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
-- TOC entry 222 (class 1259 OID 2833958)
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
-- TOC entry 223 (class 1259 OID 2833966)
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
-- TOC entry 5614 (class 0 OID 0)
-- Dependencies: 223
-- Name: composite_functions_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.composite_functions_id_seq OWNED BY bdc.composite_functions.id;


--
-- TOC entry 224 (class 1259 OID 2833968)
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
-- TOC entry 225 (class 1259 OID 2833976)
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
-- TOC entry 5615 (class 0 OID 0)
-- Dependencies: 225
-- Name: grid_ref_sys_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.grid_ref_sys_id_seq OWNED BY bdc.grid_ref_sys.id;


--
-- TOC entry 226 (class 1259 OID 2833978)
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
-- TOC entry 5616 (class 0 OID 0)
-- Dependencies: 226
-- Name: COLUMN items.assets; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.items.assets IS 'Follow the JSONSchema @jsonschemas/item-assets.json';


--
-- TOC entry 5617 (class 0 OID 0)
-- Dependencies: 226
-- Name: COLUMN items.metadata; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.items.metadata IS 'Follow the JSONSchema @jsonschemas/item-metadata.json';


--
-- TOC entry 227 (class 1259 OID 2833986)
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
-- TOC entry 5618 (class 0 OID 0)
-- Dependencies: 227
-- Name: items_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.items_id_seq OWNED BY bdc.items.id;


--
-- TOC entry 228 (class 1259 OID 2833988)
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
-- TOC entry 229 (class 1259 OID 2833996)
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
-- TOC entry 5619 (class 0 OID 0)
-- Dependencies: 229
-- Name: mime_type_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.mime_type_id_seq OWNED BY bdc.mime_type.id;


--
-- TOC entry 239 (class 1259 OID 2836580)
-- Name: mux_grid; Type: TABLE; Schema: bdc; Owner: postgres
--

CREATE TABLE bdc.mux_grid (
    id character varying NOT NULL,
    geom public.geometry(MultiPolygon,4326),
    fid bigint,
    gid integer,
    nr double precision,
    lat double precision,
    lon double precision,
    latgms character varying(15),
    longms character varying(15),
    orbita integer,
    ponto integer
);


ALTER TABLE bdc.mux_grid OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 2833998)
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
-- TOC entry 5620 (class 0 OID 0)
-- Dependencies: 230
-- Name: COLUMN providers.credentials; Type: COMMENT; Schema: bdc; Owner: postgres
--

COMMENT ON COLUMN bdc.providers.credentials IS 'Follow the JSONSchema @jsonschemas/provider-credentials.json';


--
-- TOC entry 231 (class 1259 OID 2834006)
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
-- TOC entry 5621 (class 0 OID 0)
-- Dependencies: 231
-- Name: providers_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.providers_id_seq OWNED BY bdc.providers.id;


--
-- TOC entry 232 (class 1259 OID 2834008)
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
-- TOC entry 233 (class 1259 OID 2834013)
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
-- TOC entry 234 (class 1259 OID 2834021)
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
-- TOC entry 5622 (class 0 OID 0)
-- Dependencies: 234
-- Name: resolution_unit_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.resolution_unit_id_seq OWNED BY bdc.resolution_unit.id;


--
-- TOC entry 235 (class 1259 OID 2834023)
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
-- TOC entry 236 (class 1259 OID 2834028)
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
-- TOC entry 5623 (class 0 OID 0)
-- Dependencies: 236
-- Name: tiles_id_seq; Type: SEQUENCE OWNED BY; Schema: bdc; Owner: postgres
--

ALTER SEQUENCE bdc.tiles_id_seq OWNED BY bdc.tiles.id;


--
-- TOC entry 237 (class 1259 OID 2834030)
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
-- TOC entry 238 (class 1259 OID 2834035)
-- Name: alembic_version; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.alembic_version (
    version_num character varying(32) NOT NULL
);


ALTER TABLE public.alembic_version OWNER TO postgres;

--
-- TOC entry 5304 (class 2604 OID 2834038)
-- Name: applications id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.applications ALTER COLUMN id SET DEFAULT nextval('bdc.applications_id_seq'::regclass);


--
-- TOC entry 5309 (class 2604 OID 2834039)
-- Name: bands id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.bands ALTER COLUMN id SET DEFAULT nextval('bdc.bands_id_seq'::regclass);


--
-- TOC entry 5317 (class 2604 OID 2834040)
-- Name: collections id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections ALTER COLUMN id SET DEFAULT nextval('bdc.collections_id_seq'::regclass);


--
-- TOC entry 5322 (class 2604 OID 2834041)
-- Name: composite_functions id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.composite_functions ALTER COLUMN id SET DEFAULT nextval('bdc.composite_functions_id_seq'::regclass);


--
-- TOC entry 5325 (class 2604 OID 2834042)
-- Name: grid_ref_sys id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.grid_ref_sys ALTER COLUMN id SET DEFAULT nextval('bdc.grid_ref_sys_id_seq'::regclass);


--
-- TOC entry 5328 (class 2604 OID 2834043)
-- Name: items id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.items ALTER COLUMN id SET DEFAULT nextval('bdc.items_id_seq'::regclass);


--
-- TOC entry 5331 (class 2604 OID 2834044)
-- Name: mime_type id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.mime_type ALTER COLUMN id SET DEFAULT nextval('bdc.mime_type_id_seq'::regclass);


--
-- TOC entry 5334 (class 2604 OID 2834045)
-- Name: providers id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.providers ALTER COLUMN id SET DEFAULT nextval('bdc.providers_id_seq'::regclass);


--
-- TOC entry 5339 (class 2604 OID 2834046)
-- Name: resolution_unit id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.resolution_unit ALTER COLUMN id SET DEFAULT nextval('bdc.resolution_unit_id_seq'::regclass);


--
-- TOC entry 5342 (class 2604 OID 2834047)
-- Name: tiles id; Type: DEFAULT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.tiles ALTER COLUMN id SET DEFAULT nextval('bdc.tiles_id_seq'::regclass);


--
-- TOC entry 5571 (class 0 OID 2833910)
-- Dependencies: 213
-- Data for Name: applications; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5573 (class 0 OID 2833920)
-- Dependencies: 215
-- Data for Name: band_src; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5574 (class 0 OID 2833925)
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
-- TOC entry 5576 (class 0 OID 2833935)
-- Dependencies: 218
-- Data for Name: collection_src; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5577 (class 0 OID 2833940)
-- Dependencies: 219
-- Data for Name: collections; Type: TABLE DATA; Schema: bdc; Owner: postgres
--

INSERT INTO bdc.collections VALUES (5, 'CBERS4A_WFI_L2_DN', 'CBERS4A_WFI_L2_DN', 'CBERS4A WFI Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2020-11-10 13:49:43+00', '2020-11-10 13:49:43+00', '0103000020E61000000100000005000000392BA226FAE64BC0573D601E32A93FC0392BA226FAE64BC0562B137EA98B37C0A35A4414934B47C0562B137EA98B37C0A35A4414934B47C0573D601E32A93FC0392BA226FAE64BC0573D601E32A93FC0', 1, NULL, NULL, '2020-12-01 13:47:34.414378+00', '2020-12-01 13:47:34.414378+00');
INSERT INTO bdc.collections VALUES (2, 'CBERS4A_MUX_L2_SR', 'CBERS4A_MUX_L2_SR', 'CBERS4A MUX Level2 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (113, 'CBERS4A_WFI_L3_DN', 'CBERS4A_WFI_L3_DN', 'CBERS4A WFI Level3 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2020-11-22 14:23:08+00', '2020-11-22 14:23:08+00', '0103000020E6100000010000000500000071917BBABA7150C06D904946CE0243C071917BBABA7150C0348463963DC93DC0672783A3E4F94BC0348463963DC93DC0672783A3E4F94BC06D904946CE0243C071917BBABA7150C06D904946CE0243C0', 1, NULL, NULL, '2020-12-01 13:47:34.415317+00', '2020-12-01 13:47:34.415317+00');
INSERT INTO bdc.collections VALUES (4, 'CBERS4A_MUX_L4_SR', 'CBERS4A_MUX_L4_SR', 'CBERS4A MUX Level4 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:58:39+00', '2020-11-27 14:20:24+00', '0103000020E6100000010000000500000035EF3845474E53C0545227A0892042C035EF3845474E53C07D3F355EBAD942407C61325530C244407D3F355EBAD942407C61325530C24440545227A0892042C035EF3845474E53C0545227A0892042C0', 1, NULL, NULL, '2020-12-01 13:47:34.413328+00', '2020-12-01 13:47:34.413328+00');
INSERT INTO bdc.collections VALUES (16, 'LANDSAT1_MSS_L2_DN', 'LANDSAT1_MSS_L2_DN', 'LANDSAT1 MSS Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '1973-05-21 12:38:44+00', '1973-05-21 12:38:44+00', '0103000020E61000000100000005000000874D64E6026346C0C47762D68B21E03F874D64E6026346C0C0AE264F592D0340234E27D9EA6245C0C0AE264F592D0340234E27D9EA6245C0C47762D68B21E03F874D64E6026346C0C47762D68B21E03F', 1, NULL, NULL, '2020-12-01 13:47:34.417071+00', '2020-12-01 13:47:34.417071+00');
INSERT INTO bdc.collections VALUES (6, 'CBERS4A_WFI_L2_SR', 'CBERS4A_WFI_L2_SR', 'CBERS4A WFI Level2 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:56:15+00', '2020-11-27 14:14:59+00', '0103000020E61000000100000005000000D656EC2FBBD354C00F9C33A2B4974FC0D656EC2FBBD354C0E09C11A5BDC55140D34D6210584D6240E09C11A5BDC55140D34D6210584D62400F9C33A2B4974FC0D656EC2FBBD354C00F9C33A2B4974FC0', 1, NULL, NULL, '2020-12-01 13:47:34.414378+00', '2020-12-01 13:47:34.414378+00');
INSERT INTO bdc.collections VALUES (20, 'LANDSAT7_ETM_L2_DN', 'LANDSAT7_ETM_L2_DN', 'LANDSAT7 ETM Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '1999-07-31 14:46:54+00', '1999-07-31 14:46:54+00', '0103000020E61000000100000005000000B2463D44A38852C008ABB184B55132C0B2463D44A38852C065E256410C6030C09ACC785BE9F851C065E256410C6030C09ACC785BE9F851C008ABB184B55132C0B2463D44A38852C008ABB184B55132C0', 1, NULL, NULL, '2020-12-01 13:47:34.417071+00', '2020-12-01 13:47:34.417071+00');
INSERT INTO bdc.collections VALUES (111, 'CBERS4A_WFI_L2B_SR', 'CBERS4A_WFI_L2B_SR', 'CBERS4A WFI Level2B DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:59:42+00', '2020-11-27 14:20:09+00', '0103000020E61000000100000005000000F163CC5D4BC453C024287E8CB91343C0F163CC5D4BC453C063EE5A423E383B4014AE47E17A44454063EE5A423E383B4014AE47E17A44454024287E8CB91343C0F163CC5D4BC453C024287E8CB91343C0', 1, NULL, NULL, '2020-12-01 13:47:34.415317+00', '2020-12-01 13:47:34.415317+00');
INSERT INTO bdc.collections VALUES (17, 'LANDSAT2_MSS_L2_DN', 'LANDSAT2_MSS_L2_DN', 'LANDSAT2 MSS Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '1982-02-01 14:12:48+00', '1982-02-01 14:12:48+00', '0103000020E610000001000000050000004B06802A6EA251C0B03C484F911319404B06802A6EA251C0C328081EDF4E204024D3A1D3F32051C0C328081EDF4E204024D3A1D3F32051C0B03C484F911319404B06802A6EA251C0B03C484F91131940', 1, NULL, NULL, '2020-12-01 13:47:34.417071+00', '2020-12-01 13:47:34.417071+00');
INSERT INTO bdc.collections VALUES (18, 'LANDSAT3_MSS_L2_DN', 'LANDSAT3_MSS_L2_DN', 'LANDSAT3 MSS Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '1978-04-05 12:17:12+00', '1978-04-05 12:17:12+00', '0103000020E610000001000000050000003E26529ACDE947C07B2FBE688F8736C03E26529ACDE947C0B5C5353E93B534C0E19BA6CF0ED646C0B5C5353E93B534C0E19BA6CF0ED646C07B2FBE688F8736C03E26529ACDE947C07B2FBE688F8736C0', 1, NULL, NULL, '2020-12-01 13:47:34.417071+00', '2020-12-01 13:47:34.417071+00');
INSERT INTO bdc.collections VALUES (19, 'LANDSAT5_TM_L2_DN', 'LANDSAT5_TM_L2_DN', 'LANDSAT5 TM Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2011-11-01 14:09:55+00', '2011-11-01 14:09:55+00', '0103000020E610000001000000050000003866D993C0204FC00ADAE4F049071F403866D993C0204FC025085740A12E23404E250340150B4EC025085740A12E23404E250340150B4EC00ADAE4F049071F403866D993C0204FC00ADAE4F049071F40', 1, NULL, NULL, '2020-12-01 13:47:34.417071+00', '2020-12-01 13:47:34.417071+00');
INSERT INTO bdc.collections VALUES (21, 'CBERS4_AWFI_L2_DN', 'CBERS4_AWFI_L2_DN', 'CBERS4 AWFI Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (13, 'CBERS2B_CCD_L2_DN', 'CBERS2B_CCD_L2_DN', 'CBERS2B CCD Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2010-03-01 13:10:12+00', '2010-03-01 13:10:12+00', '0103000020E61000000100000005000000FC00A436716E43C011381268B0E9F33FFC00A436716E43C04AB72572C1B902408EC9E2FE23D142C04AB72572C1B902408EC9E2FE23D142C011381268B0E9F33FFC00A436716E43C011381268B0E9F33F', 1, NULL, NULL, '2020-12-01 13:47:34.417071+00', '2020-12-01 13:47:34.417071+00');
INSERT INTO bdc.collections VALUES (23, 'CBERS4_AWFI_L2_SR', 'CBERS4_AWFI_L2_SR', 'CBERS4 AWFI Level2 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (25, 'CBERS4_MUX_L2_DN', 'CBERS4_MUX_L2_DN', 'CBERS4 MUX Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (14, 'CBERS2B_HRC_L2_DN', 'CBERS2B_HRC_L2_DN', 'CBERS2B HRC Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2010-03-01 13:20:58+00', '2010-03-01 13:21:01+00', '0103000020E6100000010000000500000067F1626188F847C00F26C5C727A442C067F1626188F847C036936FB6B96942C0F148BC3C9DBF47C036936FB6B96942C0F148BC3C9DBF47C00F26C5C727A442C067F1626188F847C00F26C5C727A442C0', 1, NULL, NULL, '2020-12-01 13:47:34.417071+00', '2020-12-01 13:47:34.417071+00');
INSERT INTO bdc.collections VALUES (27, 'CBERS4_MUX_L2_SR', 'CBERS4_MUX_L2_SR', 'CBERS4 MUX Level2 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (110, 'CBERS4A_WFI_L2B_DN', 'CBERS4A_WFI_L2B_DN', 'CBERS4A WFI Level2B DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2020-12-22 13:54:50+00', '2020-12-22 13:54:50+00', '0103000020E610000001000000050000005E4C33DDEBB249C0566133C005D992BF5E4C33DDEBB249C085EAE6E26F3320403B014D840DCB45C085EAE6E26F3320403B014D840DCB45C0566133C005D992BF5E4C33DDEBB249C0566133C005D992BF', 1, NULL, NULL, '2020-12-01 13:47:34.415317+00', '2020-12-01 13:47:34.415317+00');
INSERT INTO bdc.collections VALUES (29, 'CBERS4_PAN5M_L2_DN', 'CBERS4_PAN5M_L2_DN', 'CBERS4 PAN5M Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (30, 'CBERS4_PAN5M_L4_DN', 'CBERS4_PAN5M_L4_DN', 'CBERS4 PAN5M Level4 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (31, 'CBERS4_PAN5M_L2_SR', 'CBERS4_PAN5M_L2_SR', 'CBERS4 PAN5M Level2 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (32, 'CBERS4_PAN5M_L4_SR', 'CBERS4_PAN5M_L4_SR', 'CBERS4 PAN5M Level4 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (26, 'CBERS4_MUX_L4_DN', 'CBERS4_MUX_L4_DN', 'CBERS4 MUX Level4 DN dataset', NULL, NULL, 2, 'collection', NULL, true, '2018-01-01 13:15:18+00', '2018-01-01 13:15:18+00', '0103000020E610000001000000050000006AA164726A0146C063635E471C720AC06AA164726A0146C08BA71E69705B00C018B14F00C55845C08BA71E69705B00C018B14F00C55845C063635E471C720AC06AA164726A0146C063635E471C720AC0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (34, 'CBERS4_PAN10M_L4_DN', 'CBERS4_PAN10M_L4_DN', 'CBERS4 PAN10M Level4 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (35, 'CBERS4_PAN10M_L2_SR', 'CBERS4_PAN10M_L2_SR', 'CBERS4 PAN10M Level2 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (36, 'CBERS4_PAN10M_L4_SR', 'CBERS4_PAN10M_L4_SR', 'CBERS4 PAN10M Level4 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (28, 'CBERS4_MUX_L4_SR', 'CBERS4_MUX_L4_SR', 'CBERS4 MUX Level4 SR dataset', NULL, NULL, 2, 'collection', NULL, true, '2018-01-01 13:15:18+00', '2020-07-31 13:08:34+00', '0103000020E610000001000000050000006AA164726A0146C0BC934F8F6D790AC06AA164726A0146C0F3734353765A00C0B4AED172A0D944C0F3734353765A00C0B4AED172A0D944C0BC934F8F6D790AC06AA164726A0146C0BC934F8F6D790AC0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (38, 'AMAZONIA1_WFI_L4_DN', 'AMAZONIA1_WFI_L4_DN', 'AMAZONIA1 WFI Level4 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (39, 'AMAZONIA1_WFI_L2_SR', 'AMAZONIA1_WFI_L2_SR', 'AMAZONIA1 WFI Level2 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (40, 'AMAZONIA1_WFI_L4_SR', 'AMAZONIA1_WFI_L4_SR', 'AMAZONIA1 WFI Level4 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 13:55:50+00', '2021-01-10 13:24:19+00', '0103000020E610000001000000050000005396218E756955C08716D9CEF70B50C05396218E756955C0386744696F3C524021B0726891E96140386744696F3C524021B0726891E961408716D9CEF70B50C05396218E756955C08716D9CEF70B50C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (33, 'CBERS4_PAN10M_L2_DN', 'CBERS4_PAN10M_L2_DN', 'CBERS4 PAN10M Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2021-02-01 08:09:34+00', '2021-02-01 08:09:34+00', '0103000020E6100000010000000500000056F31C91EF5C4140992B836A835B28C056F31C91EF5C414066F50EB7430326C0EE04FBAF73D1414066F50EB7430326C0EE04FBAF73D14140992B836A835B28C056F31C91EF5C4140992B836A835B28C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (114, 'CBERS4A_WPM_L3_DN', 'CBERS4A_WPM_L3_DN', 'CBERS4A WPM Level3 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2020-12-20 14:58:15+00', '2020-12-20 14:58:15+00', '0103000020E61000000100000005000000B62C5F97E17650C076FBAC3253BA25C0B62C5F97E17650C0C3802557B1A023C0EC504D49D63450C0C3802557B1A023C0EC504D49D63450C076FBAC3253BA25C0B62C5F97E17650C076FBAC3253BA25C0', 1, NULL, NULL, '2020-12-01 13:47:34.415317+00', '2020-12-01 13:47:34.415317+00');
INSERT INTO bdc.collections VALUES (11, 'CBERS4A_WPM_L4_DN', 'CBERS4A_WPM_L4_DN', 'CBERS4A WPM Level4 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2020-12-20 14:58:15+00', '2020-12-20 14:58:15+00', '0103000020E61000000100000005000000CCD24ECDE57650C0C651B9895ABA25C0CCD24ECDE57650C0992EC4EA8FA023C0B8770DFAD23450C0992EC4EA8FA023C0B8770DFAD23450C0C651B9895ABA25C0CCD24ECDE57650C0C651B9895ABA25C0', 1, NULL, NULL, '2020-12-01 13:47:34.417071+00', '2020-12-01 13:47:34.417071+00');
INSERT INTO bdc.collections VALUES (15, 'CBERS2B_WFI_L2_DN', 'CBERS2B_WFI_L2_DN', 'CBERS2B WFI Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2010-03-01 14:48:49+00', '2010-03-01 14:48:49+00', '0103000020E61000000100000005000000F304C24EB1DD50C0C616821C94F00540F304C24EB1DD50C02506819543132740A9FB00A436794CC02506819543132740A9FB00A436794CC0C616821C94F00540F304C24EB1DD50C0C616821C94F00540', 1, NULL, NULL, '2020-12-01 13:47:34.417071+00', '2020-12-01 13:47:34.417071+00');
INSERT INTO bdc.collections VALUES (112, 'CBERS4A_MUX_L3_DN', 'CBERS4A_MUX_L3_DN', 'CBERS4A MUX Level3 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2020-12-01 13:50:58+00', '2020-12-01 13:50:58+00', '0103000020E610000001000000050000004BADF71BED5C48C0D6E1E82ADDFD1EC04BADF71BED5C48C0C171193735A01AC0A35A441493D547C0C171193735A01AC0A35A441493D547C0D6E1E82ADDFD1EC04BADF71BED5C48C0D6E1E82ADDFD1EC0', 1, NULL, NULL, '2020-12-01 13:47:34.415317+00', '2020-12-01 13:47:34.415317+00');
INSERT INTO bdc.collections VALUES (37, 'AMAZONIA1_WFI_L2_DN', 'AMAZONIA1_WFI_L2_DN', 'AMAZONIA1 WFI Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2021-03-03 12:57:42+00', '2021-03-03 14:40:46+00', '0103000020E6100000010000000500000056647440128451C0DA907F6610272FC056647440128451C0755776C1E07A0F4079B130444ECB40C0755776C1E07A0F4079B130444ECB40C0DA907F6610272FC056647440128451C0DA907F6610272FC0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (22, 'CBERS4_AWFI_L4_DN', 'CBERS4_AWFI_L4_DN', 'CBERS4 AWFI Level4 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2021-02-01 13:11:48+00', '2021-02-01 13:11:48+00', '0103000020E610000001000000050000009D4CDC2A888D48C0E197FA79532933C09D4CDC2A888D48C02BBEA1F0D9EA25C001C3F2E7DB8C43C02BBEA1F0D9EA25C001C3F2E7DB8C43C0E197FA79532933C09D4CDC2A888D48C0E197FA79532933C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (24, 'CBERS4_AWFI_L4_SR', 'CBERS4_AWFI_L4_SR', 'CBERS4 AWFI Level4 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2020-12-28 13:27:20+00', '2021-02-01 13:11:48+00', '0103000020E6100000010000000500000065C39ACAA26E4CC04337FB03E59441C065C39ACAA26E4CC02BBEA1F0D9EA25C001C3F2E7DB8C43C02BBEA1F0D9EA25C001C3F2E7DB8C43C04337FB03E59441C065C39ACAA26E4CC04337FB03E59441C0', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');
INSERT INTO bdc.collections VALUES (8, 'CBERS4A_WFI_L4_SR', 'CBERS4A_WFI_L4_SR', 'CBERS4A WFI Level4 SR dataset', NULL, NULL, NULL, 'collection', NULL, true, '2020-12-07 14:03:45+00', '2020-12-22 13:56:33+00', '0103000020E610000001000000050000009697FC4FFED64AC00AF2B391EB8619C09697FC4FFED64AC0F01307D0EF23204033C34659BF7146C0F01307D0EF23204033C34659BF7146C00AF2B391EB8619C09697FC4FFED64AC00AF2B391EB8619C0', 1, NULL, NULL, '2020-12-01 13:47:34.415317+00', '2020-12-01 13:47:34.415317+00');
INSERT INTO bdc.collections VALUES (7, 'CBERS4A_WFI_L4_DN', 'CBERS4A_WFI_L4_DN', 'CBERS4A WFI Level4 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 14:01:24+00', '2020-12-22 13:56:33+00', '0103000020E610000001000000050000004AF1F109D97150C0793E03EACD0243C04AF1F109D97150C0F01307D0EF23204033C34659BF7146C0F01307D0EF23204033C34659BF7146C0793E03EACD0243C04AF1F109D97150C0793E03EACD0243C0', 1, NULL, NULL, '2020-12-01 13:47:34.415317+00', '2020-12-01 13:47:34.415317+00');
INSERT INTO bdc.collections VALUES (3, 'CBERS4A_MUX_L4_DN', 'CBERS4A_MUX_L4_DN', 'CBERS4A MUX Level4 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2019-12-27 14:05:18+00', '2020-12-22 13:56:09+00', '0103000020E61000000100000005000000E3E313B2F3484DC076FF58880EED3DC0E3E313B2F3484DC0CCEF3499F1B6D3BFCB9C2E8B89D547C0CCEF3499F1B6D3BFCB9C2E8B89D547C076FF58880EED3DC0E3E313B2F3484DC076FF58880EED3DC0', 1, NULL, NULL, '2020-12-01 13:47:34.413328+00', '2020-12-01 13:47:34.413328+00');
INSERT INTO bdc.collections VALUES (9, 'CBERS4A_WPM_L2_DN', 'CBERS4A_WPM_L2_DN', 'CBERS4A WPM Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2020-04-01 13:19:46+00', '2020-08-16 22:00:33+00', '0103000020E610000001000000050000005A4B0169FF2A62C0601F9DBAF259D03F5A4B0169FF2A62C052EDD3F1986B5240B68311FB044844C052EDD3F1986B5240B68311FB044844C0601F9DBAF259D03F5A4B0169FF2A62C0601F9DBAF259D03F', 1, NULL, NULL, '2020-12-01 13:47:34.416189+00', '2020-12-01 13:47:34.416189+00');
INSERT INTO bdc.collections VALUES (1, 'CBERS4A_MUX_L2_DN', 'CBERS4A_MUX_L2_DN', 'CBERS4A MUX Level2 DN dataset', NULL, NULL, NULL, 'collection', NULL, true, '2020-04-05 11:01:58+00', '2021-01-10 13:24:19+00', '0103000020E61000000100000005000000C1374D9F1DA651C03C4ED1915CFED03FC1374D9F1DA651C02942EA76F6B15140E50B5A48C0A82F402942EA76F6B15140E50B5A48C0A82F403C4ED1915CFED03FC1374D9F1DA651C03C4ED1915CFED03F', 1, NULL, NULL, '2020-12-01 13:47:34.388482+00', '2020-12-01 13:47:34.388482+00');


--
-- TOC entry 5579 (class 0 OID 2833953)
-- Dependencies: 221
-- Data for Name: collections_providers; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5580 (class 0 OID 2833958)
-- Dependencies: 222
-- Data for Name: composite_functions; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5582 (class 0 OID 2833968)
-- Dependencies: 224
-- Data for Name: grid_ref_sys; Type: TABLE DATA; Schema: bdc; Owner: postgres
--

INSERT INTO bdc.grid_ref_sys VALUES (2, 'MUX_GRID', 'CBERS4 MUX TABLE', 2836580, '2021-04-05 14:02:51.926568+00', '2021-04-05 14:02:51.926568+00');


--
-- TOC entry 5584 (class 0 OID 2833978)
-- Dependencies: 226
-- Data for Name: items; Type: TABLE DATA; Schema: bdc; Owner: postgres
--

INSERT INTO bdc.items VALUES (51681, 'LANDSAT7_ETM_004072_19990731_L2_DN', 20, NULL, '1999-07-31 14:46:54+00', '1999-07-31 14:46:54+00', NULL, '{"BAND1": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072_L2_BAND1.tif", "type": "image/tiff; application=geotiff", "roles": ["data"], "common_name": "blue"}, "BAND2": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072_L2_BAND2.tif", "type": "image/tiff; application=geotiff", "roles": ["data"], "common_name": "green"}, "BAND3": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072_L2_BAND3.tif", "type": "image/tiff; application=geotiff", "roles": ["data"], "common_name": "red"}, "BAND4": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072_L2_BAND4.tif", "type": "image/tiff; application=geotiff", "roles": ["data"], "common_name": "nir"}, "BAND5": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072_L2_BAND5.tif", "type": "image/tiff; application=geotiff", "roles": ["data"], "common_name": "swir1"}, "BAND6": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072_L2_BAND6.tif", "type": "image/tiff; application=geotiff", "roles": ["data"], "common_name": "thermal"}, "BAND7": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072_L2_BAND7.tif", "type": "image/tiff; application=geotiff", "roles": ["data"], "common_name": "swir2"}, "BAND8": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMPAN_19990731_004_072_L2_BAND8.tif", "type": "image/tiff; application=geotiff", "roles": ["data"], "common_name": "pan"}, "BAND1_xml": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072_L2_BAND1.xml", "type": "application/xml", "roles": ["metadata"]}, "BAND2_xml": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072_L2_BAND2.xml", "type": "application/xml", "roles": ["metadata"]}, "BAND3_xml": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072_L2_BAND3.xml", "type": "application/xml", "roles": ["metadata"]}, "BAND4_xml": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072_L2_BAND4.xml", "type": "application/xml", "roles": ["metadata"]}, "BAND5_xml": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072_L2_BAND5.xml", "type": "application/xml", "roles": ["metadata"]}, "BAND6_xml": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072_L2_BAND6.xml", "type": "application/xml", "roles": ["metadata"]}, "BAND7_xml": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072_L2_BAND7.xml", "type": "application/xml", "roles": ["metadata"]}, "BAND8_xml": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMPAN_19990731_004_072_L2_BAND8.xml", "type": "application/xml", "roles": ["metadata"]}, "thumbnail": {"href": "/TIFF/LANDSAT7/1999_07/LANDSAT7_ETM_19990731.144148/004_072_0/2_BC_UTM_WGS84/LANDSAT_7_ETMXS_19990731_004_072.png", "type": "image/png", "roles": ["thumbnail"]}}', '{"row": 72, "name": "LANDSAT7_ETM_004072_19990731_L2_DN", "path": 4, "sensor": "ETM", "datetime": "1999-07-31T14:46:54", "satellite": "LANDSAT7", "sync_loss": null, "sun_position": {"azimuth": 43.067, "elevation": 42.3715}}', NULL, NULL, '0103000020E610000001000000050000009ACC785BE9F851C0B83D4162BB4B32C06FA0C03BF9FA51C065E256410C6030C0B2463D44A38852C083143C855C6530C0B7EEE6A90E8852C008ABB184B55132C09ACC785BE9F851C0B83D4162BB4B32C0', NULL, 4326, '2021-05-06 17:16:29.917952+00', '2021-05-06 17:16:29.917952+00');


--
-- TOC entry 5586 (class 0 OID 2833988)
-- Dependencies: 228
-- Data for Name: mime_type; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5597 (class 0 OID 2836580)
-- Dependencies: 239
-- Data for Name: mux_grid; Type: TABLE DATA; Schema: bdc; Owner: postgres
--

INSERT INTO bdc.mux_grid VALUES ('188/90', '0106000020E610000001000000010300000001000000050000002854761131FE51C0F5A58E7D63FE22407471264469C251C00024ABA3E0B62240EE3A42012ACF51C04A5CBA225CEC2040A21D92CEF10A52C03FDE9DFCDE3321402854761131FE51C0F5A58E7D63FE2240', 1, 1, 4963, 8.95919999999999916, -71.5592999999999932, 'N 08 57 33', 'O 71 33 33', 188, 90);
INSERT INTO bdc.mux_grid VALUES ('147/107', '0106000020E61000000100000001030000000100000005000000E82E91FC6ADF41C0044D3458F2EF16C0ED902559D16741C055A6D90C047F17C0659D2BA5128141C09F5CB3C45F141BC05F3B9748ACF841C050030E104E851AC0E82E91FC6ADF41C0044D3458F2EF16C0', 2, 2, 623, -6.27210000000000001, -35.3318999999999974, 'S 06 16 19', 'O 35 19 54', 147, 107);
INSERT INTO bdc.mux_grid VALUES ('147/108', '0106000020E610000001000000010300000001000000050000008FAAC1D2AEF841C0C9C04E064B851AC07B1DF69C178141C075EE58D359141BC0F8D6466E689A41C04828F423A1A91EC00D6412A4FF1142C09EFAE956921A1EC08FAAC1D2AEF841C0C9C04E064B851AC0', 3, 3, 624, -7.16790000000000038, -35.5296000000000021, 'S 07 10 04', 'O 35 31 46', 147, 108);
INSERT INTO bdc.mux_grid VALUES ('147/109', '0106000020E6100000010000000103000000010000000500000092251290021242C0B5C722D88E1A1EC02EEC10216E9A41C08D5AE8529AA91EC06D3E47B2D0B341C010B23835651F21C0D1774821652B42C0A3E8D577DFD720C092251290021242C0B5C722D88E1A1EC0', 4, 4, 626, -8.06359999999999921, -35.727800000000002, 'S 08 03 49', 'O 35 43 39', 147, 109);
INSERT INTO bdc.mux_grid VALUES ('147/110', '0106000020E6100000010000000103000000010000000500000019AD8870682B42C06B25157DDDD720C02194D622D7B341C0BFA4315B611F21C0ECBB72B74DCD41C0368DA360ECE922C0E5D42405DF4442C0E20D878268A222C019AD8870682B42C06B25157DDDD720C0', 5, 5, 628, -8.95919999999999916, -35.9264999999999972, 'S 08 57 33', 'O 35 55 35', 147, 110);
INSERT INTO bdc.mux_grid VALUES ('147/111', '0106000020E610000001000000010300000001000000050000000D4543B9E24442C05BA4714B66A222C09C20EEE854CD41C063C93813E8E922C0E79887CEE1E641C0C08D85A764B424C059BDDC9E6F5E42C0B868BEDFE26C24C00D4543B9E24442C05BA4714B66A222C0', 6, 6, 629, -9.85479999999999912, -36.1259999999999977, 'S 09 51 17', 'O 36 07 33', 147, 111);
INSERT INTO bdc.mux_grid VALUES ('148/106', '0106000020E6100000010000000103000000010000000500000018060ECDBE4142C00F86AB9F875A13C01426FF1323CA41C02437ABD29BE913C0859F980D57E341C0C5E66221097F17C0897FA7C6F25A42C0B13563EEF4EF16C018060ECDBE4142C00F86AB9F875A13C0', 7, 7, 709, -5.37619999999999987, -36.0998999999999981, 'S 05 22 34', 'O 36 05 59', 148, 106);
INSERT INTO bdc.mux_grid VALUES ('148/107', '0106000020E61000000100000001030000000100000005000000869636F0F45A42C0E54C3458F2EF16C08DF8CA4C5BE341C036A6D90C047F17C00705D1989CFC41C0C15CB3C45F141BC000A33C3C367442C070030E104E851AC0869636F0F45A42C0E54C3458F2EF16C0', 8, 8, 710, -6.27210000000000001, -36.2971000000000004, 'S 06 16 19', 'O 36 17 49', 148, 107);
INSERT INTO bdc.mux_grid VALUES ('148/108', '0106000020E61000000100000001030000000100000005000000381267C6387442C0E1C04E064B851AC014859B90A1FC41C0A0EE58D359141BC08F3EEC61F21542C03328F423A1A91EC0B4CBB797898D42C073FAE956921A1EC0381267C6387442C0E1C04E064B851AC0', 9, 9, 711, -7.16790000000000038, -36.4947000000000017, 'S 07 10 04', 'O 36 29 40', 148, 108);
INSERT INTO bdc.mux_grid VALUES ('148/109', '0106000020E61000000100000001030000000100000005000000358DB7838C8D42C093C722D88E1A1EC0D153B614F81542C06B5AE8529AA91EC013A6ECA55A2F42C03EB23835651F21C077DFED14EFA642C0D1E8D577DFD720C0358DB7838C8D42C093C722D88E1A1EC0', 10, 10, 714, -8.06359999999999921, -36.6929000000000016, 'S 08 03 49', 'O 36 41 34', 148, 109);
INSERT INTO bdc.mux_grid VALUES ('148/110', '0106000020E61000000100000001030000000100000005000000BE142E64F2A642C09925157DDDD720C0C6FB7B16612F42C0EDA4315B611F21C0922318ABD74842C0648DA360ECE922C08B3CCAF868C042C00F0E878268A222C0BE142E64F2A642C09925157DDDD720C0', 11, 11, 715, -8.95919999999999916, -36.8917000000000002, 'S 08 57 33', 'O 36 53 30', 148, 110);
INSERT INTO bdc.mux_grid VALUES ('148/111', '0106000020E61000000100000001030000000100000005000000AFACE8AC6CC042C08CA4714B66A222C03F8893DCDE4842C092C93813E8E922C085002DC26B6242C0B08D85A764B424C0F6248292F9D942C0AA68BEDFE26C24C0AFACE8AC6CC042C08CA4714B66A222C0', 12, 12, 716, -9.85479999999999912, -37.0910999999999973, 'S 09 51 17', 'O 37 05 28', 148, 111);
INSERT INTO bdc.mux_grid VALUES ('148/112', '0106000020E61000000100000001030000000100000005000000C2F350ADFDD942C0C58A3D6BE06C24C01AB81FB8736242C0586D98E45FB424C075EFA147197C42C05473B79BCC7E26C01D2BD33CA3F342C0C2905C224D3726C0C2F350ADFDD942C0C58A3D6BE06C24C0', 13, 13, 717, -10.7501999999999995, -37.2912999999999997, 'S 10 45 00', 'O 37 17 28', 148, 112);
INSERT INTO bdc.mux_grid VALUES ('149/106', '0106000020E61000000100000001030000000100000005000000B46DB3C048BD42C0C685AB9F875A13C0B98DA407AD4542C0D236ABD29BE913C02D073E01E15E42C0FAE66221097F17C028E74CBA7CD642C0ED3563EEF4EF16C0B46DB3C048BD42C0C685AB9F875A13C0', 14, 14, 801, -5.37619999999999987, -37.0649999999999977, 'S 05 22 34', 'O 37 03 54', 149, 106);
INSERT INTO bdc.mux_grid VALUES ('149/107', '0106000020E6100000010000000103000000010000000500000029FEDBE37ED642C01D4D3458F2EF16C02F607040E55E42C06EA6D90C047F17C0A76C768C267842C0C05CB3C45F141BC0A00AE22FC0EF42C06E030E104E851AC029FEDBE37ED642C01D4D3458F2EF16C0', 15, 15, 802, -6.27210000000000001, -37.2622, 'S 06 16 19', 'O 37 15 43', 149, 107);
INSERT INTO bdc.mux_grid VALUES ('149/108', '0106000020E61000000100000001030000000100000005000000E0790CBAC2EF42C0D4C04E064B851AC0BBEC40842B7842C095EE58D359141BC037A691557C9142C02E28F423A1A91EC05C335D8B130943C06CFAE956921A1EC0E0790CBAC2EF42C0D4C04E064B851AC0', 16, 16, 803, -7.16790000000000038, -37.4598999999999975, 'S 07 10 04', 'O 37 27 35', 149, 108);
INSERT INTO bdc.mux_grid VALUES ('149/109', '0106000020E61000000100000001030000000100000005000000D8F45C77160943C091C722D88E1A1EC073BB5B08829142C06B5AE8529AA91EC0B60D9299E4AA42C045B23835651F21C01B479308792243C0D9E8D577DFD720C0D8F45C77160943C091C722D88E1A1EC0', 17, 17, 806, -8.06359999999999921, -37.6580000000000013, 'S 08 03 49', 'O 37 39 28', 149, 109);
INSERT INTO bdc.mux_grid VALUES ('149/110', '0106000020E61000000100000001030000000100000005000000627CD3577C2243C0A125157DDDD720C06A63210AEBAA42C0F4A4315B611F21C0358BBD9E61C442C04C8DA360ECE922C02CA46FECF23B43C0FB0D878268A222C0627CD3577C2243C0A125157DDDD720C0', 18, 18, 807, -8.95919999999999916, -37.8567999999999998, 'S 08 57 33', 'O 37 51 24', 149, 110);
INSERT INTO bdc.mux_grid VALUES ('149/111', '0106000020E610000001000000010300000001000000050000004C148EA0F63B43C077A4714B66A222C0DBEF38D068C442C07FC93813E8E922C02568D2B5F5DD42C0BE8D85A764B424C0958C2786835543C0B668BEDFE26C24C04C148EA0F63B43C077A4714B66A222C0', 19, 19, 808, -9.85479999999999912, -38.0563000000000002, 'S 09 51 17', 'O 38 03 22', 149, 111);
INSERT INTO bdc.mux_grid VALUES ('149/112', '0106000020E61000000100000001030000000100000005000000665BF6A0875543C0D18A3D6BE06C24C0BE1FC5ABFDDD42C0636D98E45FB424C01857473BA3F742C04173B79BCC7E26C0C09278302D6F43C0AF905C224D3726C0665BF6A0875543C0D18A3D6BE06C24C0', 20, 20, 809, -10.7501999999999995, -38.2563999999999993, 'S 10 45 00', 'O 38 15 23', 149, 112);
INSERT INTO bdc.mux_grid VALUES ('149/113', '0106000020E610000001000000010300000001000000050000008B3200B4316F43C009F5386F4A3726C05DDEA4F9ABF742C028FAEA60C77E26C0302298986C1143C0644D6CCD224928C05F76F352F28843C04448BADBA50128C08B3200B4316F43C009F5386F4A3726C0', 21, 21, 811, -11.6454000000000004, -38.4573999999999998, 'S 11 38 43', 'O 38 27 26', 149, 113);
INSERT INTO bdc.mux_grid VALUES ('149/114', '0106000020E610000001000000010300000001000000050000006BDA7441F78843C0CAD99AE8A20128C0B76BC023761143C02FA022181D4928C0F88DA045542B43C0A7F4F8CA65132AC0ABFC5463D5A243C0432E719BEBCB29C06BDA7441F78843C0CAD99AE8A20128C0', 22, 22, 812, -12.5404999999999998, -38.6593000000000018, 'S 12 32 25', 'O 38 39 33', 149, 114);
INSERT INTO bdc.mux_grid VALUES ('149/115', '0106000020E61000000100000001030000000100000005000000330D4CBFDAA243C09194D966E8CB29C0A5BE64A25E2B43C09F8350985F132AC0D91307CA5C4543C03BF3952094DD2BC06762EEE6D8BC43C02D041FEF1C962BC0330D4CBFDAA243C09194D966E8CB29C0', 23, 23, 813, -13.4354999999999993, -38.8620999999999981, 'S 13 26 07', 'O 38 51 43', 149, 115);
INSERT INTO bdc.mux_grid VALUES ('149/116', '0106000020E6100000010000000103000000010000000500000017BA14B3DEBC43C0FCFF6D7719962BC009C9AEFD674543C0CA52666D8DDD2BC0D839B9BE885F43C018481B58ACA72DC0E62A1F74FFD643C049F5226238602DC017BA14B3DEBC43C0FCFF6D7719962BC0', 24, 24, 814, -14.3302999999999994, -39.0660000000000025, 'S 14 19 49', 'O 39 03 57', 149, 116);
INSERT INTO bdc.mux_grid VALUES ('149/117', '0106000020E61000000100000001030000000100000005000000BD1F6FB305D743C0CC8F90A534602DC0046208CF945F43C094B1F120A5A72DC0316C7BCFDA7943C03D63B5F8AC712FC0EA29E2B34BF143C07441547D3C2A2FC0BD1F6FB305D743C0CC8F90A534602DC0', 25, 25, 816, -15.2249999999999996, -39.2708999999999975, 'S 15 13 29', 'O 39 16 15', 149, 117);
INSERT INTO bdc.mux_grid VALUES ('149/118', '0106000020E61000000100000001030000000100000005000000A42A9A6952F143C009C9EF79382A2FC0AEBEB8C2E77943C099D6D039A5712FC0E2658EBC559443C0CF534943CA9D30C0D8D16F63C00B44C007CD58E3137A30C0A42A9A6952F143C009C9EF79382A2FC0', 26, 26, 818, -16.1193999999999988, -39.4771000000000001, 'S 16 07 09', 'O 39 28 37', 149, 118);
INSERT INTO bdc.mux_grid VALUES ('149/119', '0106000020E61000000100000001030000000100000005000000A31A1693C70B44C078B52FBD117A30C08E838A99639443C007D4EF1DC69D30C0455C6C5CFCAE43C0A26044C1B08231C058F3F755602644C013428460FC5E31C0A31A1693C70B44C078B52FBD117A30C0', 27, 27, 819, -17.0137, -39.6846000000000032, 'S 17 00 49', 'O 39 41 04', 149, 119);
INSERT INTO bdc.mux_grid VALUES ('149/120', '0106000020E610000001000000010300000001000000050000002CA55E03682644C0EECABF14FA5E31C0CDA9892A0BAF43C06D51CE53AC8231C08C56A09DD1C943C0547FD834896732C0EB5175762E4144C0D6F8C9F5D64332C02CA55E03682644C0EECABF14FA5E31C0', 28, 28, 820, -17.9076999999999984, -39.8933999999999997, 'S 17 54 27', 'O 39 53 36', 149, 120);
INSERT INTO bdc.mux_grid VALUES ('149/121', '0106000020E6100000010000000103000000010000000500000037F1BEA5364144C074932D83D44332C09D9EDB64E1C943C0335EE27C846732C0E94BBA88D8E443C0316C7DDA524C33C0829E9DC92D5C44C073A1C8E0A22833C037F1BEA5364144C074932D83D44332C0', 29, 29, 822, -18.8016000000000005, -40.1037000000000035, 'S 18 48 05', 'O 40 06 13', 149, 121);
INSERT INTO bdc.mux_grid VALUES ('149/122', '0106000020E610000001000000010300000001000000050000009904427F365C44C04B3AFE45A02833C08939B451E9E443C07CB472D54D4C33C0FCDE6242140044C00DDF59EC0C3134C00BAAF06F617744C0DC64E55C5F0D34C09904427F365C44C04B3AFE45A02833C0', 30, 30, 823, -19.6951000000000001, -40.3155000000000001, 'S 19 41 42', 'O 40 18 55', 149, 122);
INSERT INTO bdc.mux_grid VALUES ('150/105', '0106000020E61000000100000001030000000100000005000000B472EC16A81F43C050274D5A1B8A0FC0638A359F0AA842C04CE973F6235410C06013A47233C142C051BDD50CA0E913C0B0FB5AEAD03843C0AE6788C3895A13C0B472EC16A81F43C050274D5A1B8A0FC0', 31, 31, 899, -4.48029999999999973, -37.8333999999999975, 'S 04 28 49', 'O 37 50 00', 150, 105);
INSERT INTO bdc.mux_grid VALUES ('150/106', '0106000020E610000001000000010300000001000000050000005DD558B4D23843C00B86AB9F875A13C058F549FB36C142C02137ABD29BE913C0C96EE3F46ADA42C0C2E66221097F17C0CF4EF2AD065243C0AD3563EEF4EF16C05DD558B4D23843C00B86AB9F875A13C0', 32, 32, 900, -5.37619999999999987, -38.0302000000000007, 'S 05 22 34', 'O 38 01 48', 150, 106);
INSERT INTO bdc.mux_grid VALUES ('150/107', '0106000020E61000000100000001030000000100000005000000D06581D7085243C0DB4C3458F2EF16C0CEC715346FDA42C036A6D90C047F17C048D41B80B0F342C0025DB3C45F141BC04B7287234A6B43C0A7030E104E851AC0D06581D7085243C0DB4C3458F2EF16C0', 33, 33, 901, -6.27210000000000001, -38.2274000000000029, 'S 06 16 19', 'O 38 13 38', 150, 107);
INSERT INTO bdc.mux_grid VALUES ('150/108', '0106000020E6100000010000000103000000010000000500000089E1B1AD4C6B43C010C14E064B851AC06454E677B5F342C0CFEE58D359141BC0E00D3749060D43C06328F423A1A91EC0059B027F9D8443C0A5FAE956921A1EC089E1B1AD4C6B43C010C14E064B851AC0', 34, 34, 903, -7.16790000000000038, -38.4249999999999972, 'S 07 10 04', 'O 38 25 30', 150, 108);
INSERT INTO bdc.mux_grid VALUES ('150/109', '0106000020E610000001000000010300000001000000050000007D5C026BA08443C0CCC722D88E1A1EC0182301FC0B0D43C0A45AE8529AA91EC05775378D6E2643C019B23835651F21C0BDAE38FC029E43C0ADE8D577DFD720C07D5C026BA08443C0CCC722D88E1A1EC0', 35, 35, 905, -8.06359999999999921, -38.6231999999999971, 'S 08 03 49', 'O 38 37 23', 150, 109);
INSERT INTO bdc.mux_grid VALUES ('150/110', '0106000020E6100000010000000103000000010000000500000003E4784B069E43C07625157DDDD720C00BCBC6FD742643C0C9A4315B611F21C0D6F26292EB3F43C03F8DA360ECE922C0CE0B15E07CB743C0EB0D878268A222C003E4784B069E43C07625157DDDD720C0', 36, 36, 906, -8.95919999999999916, -38.8220000000000027, 'S 08 57 33', 'O 38 49 19', 150, 110);
INSERT INTO bdc.mux_grid VALUES ('150/111', '0106000020E61000000100000001030000000100000005000000FC7B339480B743C062A4714B66A222C07B57DEC3F23F43C073C93813E8E922C0C6CF77A97F5943C0D28D85A764B424C047F4CC790DD143C0C068BEDFE26C24C0FC7B339480B743C062A4714B66A222C0', 37, 37, 907, -9.85479999999999912, -39.0213999999999999, 'S 09 51 17', 'O 39 01 17', 150, 111);
INSERT INTO bdc.mux_grid VALUES ('150/112', '0106000020E61000000100000001030000000100000005000000FCC29B9411D143C0EB8A3D6BE06C24C063876A9F875943C0746D98E45FB424C0BBBEEC2E2D7343C03073B79BCC7E26C053FA1D24B7EA43C0A6905C224D3726C0FCC29B9411D143C0EB8A3D6BE06C24C0', 38, 38, 909, -10.7501999999999995, -39.2216000000000022, 'S 10 45 00', 'O 39 13 17', 150, 112);
INSERT INTO bdc.mux_grid VALUES ('150/113', '0106000020E610000001000000010300000001000000050000003E9AA5A7BBEA43C0ECF4386F4A3726C0FD454AED357343C018FAEA60C77E26C0D6893D8CF68C43C0B24D6CCD224928C017DE98467C0444C08648BADBA50128C03E9AA5A7BBEA43C0ECF4386F4A3726C0', 39, 39, 910, -11.6454000000000004, -39.4226000000000028, 'S 11 38 43', 'O 39 25 21', 150, 113);
INSERT INTO bdc.mux_grid VALUES ('150/114', '0106000020E610000001000000010300000001000000050000000E421A35810444C016DA9AE8A20128C06DD36517008D43C071A022181D4928C0A8F54539DEA643C086F4F8CA65132AC04A64FA565F1E44C02C2E719BEBCB29C00E421A35810444C016DA9AE8A20128C0', 40, 40, 911, -12.5404999999999998, -39.6244000000000014, 'S 12 32 25', 'O 39 37 27', 150, 114);
INSERT INTO bdc.mux_grid VALUES ('150/115', '0106000020E61000000100000001030000000100000005000000E874F1B2641E44C06C94D966E8CB29C04A260A96E8A643C0868350985F132AC0787BACBDE6C043C0C0F2952094DD2BC017CA93DA623844C0A7031FEF1C962BC0E874F1B2641E44C06C94D966E8CB29C0', 41, 41, 912, -13.4354999999999993, -39.8271999999999977, 'S 13 26 07', 'O 39 49 38', 150, 115);
INSERT INTO bdc.mux_grid VALUES ('150/116', '0106000020E610000001000000010300000001000000050000008F21BAA6683844C097FF6D7719962BC0A43054F1F1C043C05252666D8DDD2BC074A15EB212DB43C0BD471B58ACA72DC06092C467895244C003F5226238602DC08F21BAA6683844C097FF6D7719962BC0', 42, 42, 914, -14.3302999999999994, -40.0311000000000021, 'S 14 19 49', 'O 40 01 51', 150, 116);
INSERT INTO bdc.mux_grid VALUES ('150/117', '0106000020E61000000100000001030000000100000005000000718714A78F5244C0618F90A534602DC096C9ADC21EDB43C03EB1F120A5A72DC0CED320C364F543C08363B5F8AC712FC0A89187A7D56C44C0A641547D3C2A2FC0718714A78F5244C0618F90A534602DC0', 43, 43, 915, -15.2249999999999996, -40.2361000000000004, 'S 15 13 29', 'O 40 14 09', 150, 117);
INSERT INTO bdc.mux_grid VALUES ('150/118', '0106000020E6100000010000000103000000010000000500000025923F5DDC6C44C063C9EF79382A2FC051265EB671F543C0DFD6D039A5712FC07FCD33B0DF0F44C0CE534943CA9D30C0533915574A8744C012CD58E3137A30C025923F5DDC6C44C063C9EF79382A2FC0', 44, 44, 917, -16.1193999999999988, -40.4421999999999997, 'S 16 07 09', 'O 40 26 32', 150, 118);
INSERT INTO bdc.mux_grid VALUES ('150/119', '0106000020E610000001000000010300000001000000050000005382BB86518744C073B52FBD117A30C01DEB2F8DED0F44C00BD4EF1DC69D30C0CCC31150862A44C0756044C1B08231C0035B9D49EAA144C0DD418460FC5E31C05382BB86518744C073B52FBD117A30C0', 45, 45, 918, -17.0137, -40.6497000000000028, 'S 17 00 49', 'O 40 38 58', 150, 119);
INSERT INTO bdc.mux_grid VALUES ('150/120', '0106000020E61000000100000001030000000100000005000000CD0C04F7F1A144C0BCCABF14FA5E31C06E112F1E952A44C03951CE53AC8231C02DBE45915B4544C0317FD834896732C08EB91A6AB8BC44C0B4F8C9F5D64332C0CD0C04F7F1A144C0BCCABF14FA5E31C0', 46, 46, 920, -17.9076999999999984, -40.8584999999999994, 'S 17 54 27', 'O 40 51 30', 150, 120);
INSERT INTO bdc.mux_grid VALUES ('150/121', '0106000020E61000000100000001030000000100000005000000E7586499C0BC44C04D932D83D44332C02B0681586B4544C0145EE27C846732C078B35F7C626044C0226C7DDA524C33C0350643BDB7D744C05AA1C8E0A22833C0E7586499C0BC44C04D932D83D44332C0', 47, 47, 921, -18.8016000000000005, -41.0688000000000031, 'S 18 48 05', 'O 41 04 07', 150, 121);
INSERT INTO bdc.mux_grid VALUES ('150/122', '0106000020E610000001000000010300000001000000050000005D6CE772C0D744C02E3AFE45A02833C008A15945736044C072B472D54D4C33C0754608369E7B44C0D4DE59EC0C3134C0CA119663EBF244C08F64E55C5F0D34C05D6CE772C0D744C02E3AFE45A02833C0', 48, 48, 922, -19.6951000000000001, -41.2807000000000031, 'S 19 41 42', 'O 41 16 50', 150, 122);
INSERT INTO bdc.mux_grid VALUES ('150/123', '0106000020E61000000100000001030000000100000005000000A7DA67A4F4F244C09BC37B985C0D34C00CCE0F0AB07B44C0BCEC7197073134C0953B3701129744C0858E01A2B61535C030488F9B560E45C063650BA30BF234C0A7DA67A4F4F244C09BC37B985C0D34C0', 49, 49, 923, -20.5884999999999998, -41.4941999999999993, 'S 20 35 18', 'O 41 29 38', 150, 123);
INSERT INTO bdc.mux_grid VALUES ('150/124', '0106000020E6100000010000000103000000010000000500000069C7C16C600E45C0116674B308F234C0E50455EA249744C041353CFAB01535C0000D9041C1B244C071CB2C304FFA35C084CFFCC3FC2945C041FC64E9A6D635C069C7C16C600E45C0116674B308F234C0', 50, 50, 925, -21.4816000000000003, -41.7094000000000023, 'S 21 28 53', 'O 41 42 33', 150, 124);
INSERT INTO bdc.mux_grid VALUES ('150/125', '0106000020E61000000100000001030000000100000005000000019A2A2B072A45C0EF98F3CCA3D635C011F9924AD5B244C07C964E3249FA35C08459E87DAFCE44C0E51769C8D5DE36C074FA7F5EE14545C0581A0E6330BB36C0019A2A2B072A45C0EF98F3CCA3D635C0', 51, 51, 926, -22.3744000000000014, -41.9264999999999972, 'S 22 22 27', 'O 41 55 35', 150, 125);
INSERT INTO bdc.mux_grid VALUES ('151/105', '0106000020E6100000010000000103000000010000000500000060DA910A329B43C0EF264D5A1B8A0FC0FEF1DA92942343C031E973F6235410C0FB7A4966BD3C43C038BDD50CA0E913C05D6300DE5AB443C07F6788C3895A13C060DA910A329B43C0EF264D5A1B8A0FC0', 52, 52, 1005, -4.48029999999999973, -38.7984999999999971, 'S 04 28 49', 'O 38 47 54', 151, 105);
INSERT INTO bdc.mux_grid VALUES ('151/106', '0106000020E61000000100000001030000000100000005000000033DFEA75CB443C0E485AB9F875A13C0FE5CEFEEC03C43C0FA36ABD29BE913C071D688E8F45543C0DDE66221097F17C075B697A190CD43C0C73563EEF4EF16C0033DFEA75CB443C0E485AB9F875A13C0', 53, 53, 1006, -5.37619999999999987, -38.9953000000000003, 'S 05 22 34', 'O 38 59 43', 151, 106);
INSERT INTO bdc.mux_grid VALUES ('151/107', '0106000020E6100000010000000103000000010000000500000072CD26CB92CD43C0FC4C3458F2EF16C0782FBB27F95543C04DA6D90C047F17C0EF3BC1733A6F43C09A5CB3C45F141BC0E9D92C17D4E643C049030E104E851AC072CD26CB92CD43C0FC4C3458F2EF16C0', 54, 54, 1008, -6.27210000000000001, -39.1925000000000026, 'S 06 16 19', 'O 39 11 33', 151, 107);
INSERT INTO bdc.mux_grid VALUES ('151/108', '0106000020E61000000100000001030000000100000005000000264957A1D6E643C0B1C04E064B851AC009BC8B6B3F6F43C067EE58D359141BC08775DC3C908843C03C28F423A1A91EC0A402A872270044C085FAE956921A1EC0264957A1D6E643C0B1C04E064B851AC0', 55, 55, 1009, -7.16790000000000038, -39.3902000000000001, 'S 07 10 04', 'O 39 23 24', 151, 108);
INSERT INTO bdc.mux_grid VALUES ('151/109', '0106000020E610000001000000010300000001000000050000001EC4A75E2A0044C0ACC722D88E1A1EC0BB8AA6EF958843C0845AE8529AA91EC0FDDCDC80F8A143C047B23835651F21C06016DEEF8C1944C0DBE8D577DFD720C01EC4A75E2A0044C0ACC722D88E1A1EC0', 56, 56, 1011, -8.06359999999999921, -39.5882999999999967, 'S 08 03 49', 'O 39 35 18', 151, 109);
INSERT INTO bdc.mux_grid VALUES ('151/110', '0106000020E61000000100000001030000000100000005000000A84B1E3F901944C0A225157DDDD720C0B0326CF1FEA143C0F6A4315B611F21C0785A088675BB43C02D8DA360ECE922C07073BAD3063344C0D90D878268A222C0A84B1E3F901944C0A225157DDDD720C0', 57, 57, 1012, -8.95919999999999916, -39.7871000000000024, 'S 08 57 33', 'O 39 47 13', 151, 110);
INSERT INTO bdc.mux_grid VALUES ('151/111', '0106000020E610000001000000010300000001000000050000009AE3D8870A3344C053A4714B66A222C02ABF83B77CBB43C059C93813E8E922C075371D9D09D543C0B78D85A764B424C0E55B726D974C44C0AF68BEDFE26C24C09AE3D8870A3344C053A4714B66A222C0', 58, 58, 1014, -9.85479999999999912, -39.9866000000000028, 'S 09 51 17', 'O 39 59 11', 151, 111);
INSERT INTO bdc.mux_grid VALUES ('151/112', '0106000020E610000001000000010300000001000000050000009E2A41889B4C44C0D78A3D6BE06C24C0F5EE0F9311D543C06B6D98E45FB424C052269222B7EE43C06773B79BCC7E26C0F961C317416644C0D3905C224D3726C09E2A41889B4C44C0D78A3D6BE06C24C0', 59, 59, 1015, -10.7501999999999995, -40.1867000000000019, 'S 10 45 00', 'O 40 11 12', 151, 112);
INSERT INTO bdc.mux_grid VALUES ('151/113', '0106000020E61000000100000001030000000100000005000000E2014B9B456644C01CF5386F4A3726C0B3ADEFE0BFEE43C03DFAEA60C77E26C087F1E27F800844C0964D6CCD224928C0B6453E3A068044C07548BADBA50128C0E2014B9B456644C01CF5386F4A3726C0', 60, 60, 1016, -11.6454000000000004, -40.3877000000000024, 'S 11 38 43', 'O 40 23 15', 151, 113);
INSERT INTO bdc.mux_grid VALUES ('151/114', '0106000020E610000001000000010300000001000000050000009EA9BF280B8044C00EDA9AE8A20128C00C3B0B0B8A0844C05FA022181D4928C0455DEB2C682244C035F4F8CA65132AC0D5CB9F4AE99944C0E52D719BEBCB29C09EA9BF280B8044C00EDA9AE8A20128C0', 61, 61, 1017, -12.5404999999999998, -40.5895999999999972, 'S 12 32 25', 'O 40 35 22', 151, 114);
INSERT INTO bdc.mux_grid VALUES ('151/115', '0106000020E6100000010000000103000000010000000500000068DC96A6EE9944C02B94D966E8CB29C0FD8DAF89722244C0278350985F132AC032E351B1703C44C0E0F2952094DD2BC09F3139CEECB344C0E4031FEF1C962BC068DC96A6EE9944C02B94D966E8CB29C0', 62, 62, 1019, -13.4354999999999993, -40.7924000000000007, 'S 13 26 07', 'O 40 47 32', 151, 115);
INSERT INTO bdc.mux_grid VALUES ('151/116', '0106000020E6100000010000000103000000010000000500000056895F9AF2B344C0B2FF6D7719962BC02598F9E47B3C44C09752666D8DDD2BC0F60804A69C5644C0FF471B58ACA72DC026FA695B13CE44C01AF5226238602DC056895F9AF2B344C0B2FF6D7719962BC0', 63, 63, 1020, -14.3302999999999994, -40.9962000000000018, 'S 14 19 49', 'O 40 59 46', 151, 116);
INSERT INTO bdc.mux_grid VALUES ('151/117', '0106000020E610000001000000010300000001000000050000000CEFB99A19CE44C0938F90A534602DC0543153B6A85644C05EB1F120A5A72DC0833BC6B6EE7044C02463B5F8AC712FC03BF92C9B5FE844C05941547D3C2A2FC00CEFB99A19CE44C0938F90A534602DC0', 64, 64, 1021, -15.2249999999999996, -41.2012, 'S 15 13 29', 'O 41 12 04', 151, 117);
INSERT INTO bdc.mux_grid VALUES ('151/118', '0106000020E61000000100000001030000000100000005000000E0F9E45066E844C0FEC8EF79382A2FC0C78D03AAFB7044C0A3D6D039A5712FC0FE34D9A3698B44C0F2534943CA9D30C017A1BA4AD40245C021CD58E3137A30C0E0F9E45066E844C0FEC8EF79382A2FC0', 65, 65, 1023, -16.1193999999999988, -41.4074000000000026, 'S 16 07 09', 'O 41 24 26', 151, 118);
INSERT INTO bdc.mux_grid VALUES ('151/119', '0106000020E61000000100000001030000000100000005000000E6E9607ADB0245C091B52FBD117A30C0D152D580778B44C01FD4EF1DC69D30C0802BB74310A644C08A6044C1B08231C095C2423D741D45C0FC418460FC5E31C0E6E9607ADB0245C091B52FBD117A30C0', 66, 66, 1025, -17.0137, -41.6148000000000025, 'S 17 00 49', 'O 41 36 53', 151, 119);
INSERT INTO bdc.mux_grid VALUES ('151/120', '0106000020E610000001000000010300000001000000050000007674A9EA7B1D45C0D3CABF14FA5E31C01679D4111FA644C05051CE53AC8231C0D725EB84E5C044C0477FD834896732C03721C05D423845C0C9F8C9F5D64332C07674A9EA7B1D45C0D3CABF14FA5E31C0', 67, 67, 1026, -17.9076999999999984, -41.8237000000000023, 'S 17 54 27', 'O 41 49 25', 151, 120);
INSERT INTO bdc.mux_grid VALUES ('151/121', '0106000020E610000001000000010300000001000000050000007DC0098D4A3845C069932D83D44332C0E36D264CF5C044C0265EE27C846732C0311B0570ECDB44C0346C7DDA524C33C0CA6DE8B0415345C076A1C8E0A22833C07DC0098D4A3845C069932D83D44332C0', 68, 68, 1027, -18.8016000000000005, -42.0339999999999989, 'S 18 48 05', 'O 42 02 02', 151, 121);
INSERT INTO bdc.mux_grid VALUES ('151/122', '0106000020E6100000010000000103000000010000000500000003D48C664A5345C0453AFE45A02833C0D208FF38FDDB44C07EB472D54D4C33C03EAEAD2928F744C0E0DE59EC0C3134C072793B57756E45C0A764E55C5F0D34C003D48C664A5345C0453AFE45A02833C0', 69, 69, 1028, -19.6951000000000001, -42.2458000000000027, 'S 19 41 42', 'O 42 14 44', 151, 122);
INSERT INTO bdc.mux_grid VALUES ('151/123', '0106000020E6100000010000000103000000010000000500000036420D987E6E45C0B9C37B985C0D34C0BD35B5FD39F744C0D1EC7197073134C03FA3DCF49B1245C0598E01A2B61535C0B7AF348FE08945C042650BA30BF234C036420D987E6E45C0B9C37B985C0D34C0', 70, 70, 1030, -20.5884999999999998, -42.4592999999999989, 'S 20 35 18', 'O 42 27 33', 151, 123);
INSERT INTO bdc.mux_grid VALUES ('151/124', '0106000020E61000000100000001030000000100000005000000142F6760EA8945C0E46574B308F234C0906CFADDAE1245C015353CFAB01535C0B47435354B2E45C085CB2C304FFA35C03837A2B786A545C054FC64E9A6D635C0142F6760EA8945C0E46574B308F234C0', 71, 71, 1031, -21.4816000000000003, -42.6745999999999981, 'S 21 28 53', 'O 42 40 28', 151, 124);
INSERT INTO bdc.mux_grid VALUES ('151/125', '0106000020E61000000100000001030000000100000005000000BE01D01E91A545C00099F3CCA3D635C0AC60383E5F2E45C097964E3249FA35C01EC18D71394A45C0011869C8D5DE36C0306225526BC145C06A1A0E6330BB36C0BE01D01E91A545C00099F3CCA3D635C0', 72, 72, 1032, -22.3744000000000014, -42.8917000000000002, 'S 22 22 27', 'O 42 53 30', 151, 125);
INSERT INTO bdc.mux_grid VALUES ('152/104', '0106000020E61000000100000001030000000100000005000000C621EDBE9AFD43C0F061E99F0E5F08C061ACB2DEFB8543C029B407913E7D09C0EBDFB4B21B9F43C07EF04658275410C05055EF92BA1644C0C48E6FBF1E8A0FC0C621EDBE9AFD43C0F061E99F0E5F08C0', 73, 73, 1116, -3.58429999999999982, -39.5671999999999997, 'S 03 35 03', 'O 39 34 01', 152, 104);
INSERT INTO bdc.mux_grid VALUES ('152/105', '0106000020E61000000100000001030000000100000005000000044237FEBB1644C0D8264D5A1B8A0FC0AB5980861E9F43C01AE973F6235410C0A7E2EE5947B843C0FEBCD50CA0E913C000CBA5D1E42F44C04F6788C3895A13C0044237FEBB1644C0D8264D5A1B8A0FC0', 74, 74, 1117, -4.48029999999999973, -39.7635999999999967, 'S 04 28 49', 'O 39 45 49', 152, 105);
INSERT INTO bdc.mux_grid VALUES ('152/106', '0106000020E610000001000000010300000001000000050000009FA4A39BE62F44C0BE85AB9F875A13C0A3C494E24AB843C0C936ABD29BE913C0163E2EDC7ED143C0B1E66221097F17C0121E3D951A4944C0A63563EEF4EF16C09FA4A39BE62F44C0BE85AB9F875A13C0', 75, 75, 1118, -5.37619999999999987, -39.9605000000000032, 'S 05 22 34', 'O 39 57 37', 152, 106);
INSERT INTO bdc.mux_grid VALUES ('152/107', '0106000020E610000001000000010300000001000000050000001935CCBE1C4944C0CD4C3458F2EF16C01797601B83D143C028A6D90C047F17C08CA36667C4EA43C0395CB3C45F141BC08E41D20A5E6244C0DF020E104E851AC01935CCBE1C4944C0CD4C3458F2EF16C0', 76, 76, 1119, -6.27210000000000001, -40.1576999999999984, 'S 06 16 19', 'O 40 09 27', 152, 107);
INSERT INTO bdc.mux_grid VALUES ('152/108', '0106000020E61000000100000001030000000100000005000000C3B0FC94606244C051C04E064B851AC0A723315FC9EA43C009EE58D359141BC027DD81301A0444C02328F423A1A91EC0436A4D66B17B44C06CFAE956921A1EC0C3B0FC94606244C051C04E064B851AC0', 77, 77, 1120, -7.16790000000000038, -40.3552999999999997, 'S 07 10 04', 'O 40 21 19', 152, 108);
INSERT INTO bdc.mux_grid VALUES ('152/109', '0106000020E61000000100000001030000000100000005000000C22B4D52B47B44C08CC722D88E1A1EC05CF24BE31F0444C0645AE8529AA91EC0A0448274821D44C042B23835651F21C0057E83E3169544C0D6E8D577DFD720C0C22B4D52B47B44C08CC722D88E1A1EC0', 78, 78, 1122, -8.06359999999999921, -40.5534999999999997, 'S 08 03 49', 'O 40 33 12', 152, 109);
INSERT INTO bdc.mux_grid VALUES ('152/110', '0106000020E610000001000000010300000001000000050000003CB3C3321A9544C0A825157DDDD720C0549A11E5881D44C0F1A4315B611F21C01DC2AD79FF3644C04A8DA360ECE922C006DB5FC790AE44C0000E878268A222C03CB3C3321A9544C0A825157DDDD720C0', 79, 79, 1124, -8.95919999999999916, -40.7522999999999982, 'S 08 57 33', 'O 40 45 08', 152, 110);
INSERT INTO bdc.mux_grid VALUES ('152/111', '0106000020E610000001000000010300000001000000050000003A4B7E7B94AE44C072A4714B66A222C0CA2629AB063744C079C93813E8E922C0129FC290935044C0B88D85A764B424C083C3176121C844C0B268BEDFE26C24C03A4B7E7B94AE44C072A4714B66A222C0', 80, 80, 1125, -9.85479999999999912, -40.9517000000000024, 'S 09 51 17', 'O 40 57 06', 152, 111);
INSERT INTO bdc.mux_grid VALUES ('152/112', '0106000020E610000001000000010300000001000000050000004192E67B25C844C0D78A3D6BE06C24C09956B5869B5044C06A6D98E45FB424C0F48D3716416A44C04873B79BCC7E26C09BC9680BCBE144C0B5905C224D3726C04192E67B25C844C0D78A3D6BE06C24C0', 81, 81, 1126, -10.7501999999999995, -41.1518999999999977, 'S 10 45 00', 'O 41 09 06', 152, 112);
INSERT INTO bdc.mux_grid VALUES ('152/113', '0106000020E610000001000000010300000001000000050000008169F08ECFE144C0FFF4386F4A3726C0521595D4496A44C01FFAEA60C77E26C0285988730A8444C09C4D6CCD224928C056ADE32D90FB44C07A48BADBA50128C08169F08ECFE144C0FFF4386F4A3726C0', 82, 82, 1127, -11.6454000000000004, -41.3528999999999982, 'S 11 38 43', 'O 41 21 10', 152, 113);
INSERT INTO bdc.mux_grid VALUES ('152/114', '0106000020E610000001000000010300000001000000050000006211651C95FB44C002DA9AE8A20128C09DA2B0FE138444C070A022181D4928C0D9C49020F29D44C0A7F4F8CA65132AC09D33453E731545C0392E719BEBCB29C06211651C95FB44C002DA9AE8A20128C0', 83, 83, 1128, -12.5404999999999998, -41.5546999999999969, 'S 12 32 25', 'O 41 33 16', 152, 114);
INSERT INTO bdc.mux_grid VALUES ('152/115', '0106000020E6100000010000000103000000010000000500000014443C9A781545C09294D966E8CB29C086F5547DFC9D44C0A28350985F132AC0B44AF7A4FAB744C0BEF2952094DD2BC04299DEC1762F45C0AE031FEF1C962BC014443C9A781545C09294D966E8CB29C0', 84, 84, 1129, -13.4354999999999993, -41.7575000000000003, 'S 13 26 07', 'O 41 45 27', 152, 115);
INSERT INTO bdc.mux_grid VALUES ('152/116', '0106000020E61000000100000001030000000100000005000000F4F0048E7C2F45C07CFF6D7719962BC0E5FF9ED805B844C04B52666D8DDD2BC0BB70A99926D244C018481B58ACA72DC0CA610F4F9D4945C049F5226238602DC0F4F0048E7C2F45C07CFF6D7719962BC0', 85, 85, 1130, -14.3302999999999994, -41.9613999999999976, 'S 14 19 49', 'O 41 57 41', 152, 116);
INSERT INTO bdc.mux_grid VALUES ('152/117', '0106000020E61000000100000001030000000100000005000000A7565F8EA34945C0C88F90A534602DC0EF98F8A932D244C090B1F120A5A72DC01CA36BAA78EC44C03A63B5F8AC712FC0D460D28EE96345C07041547D3C2A2FC0A7565F8EA34945C0C88F90A534602DC0', 86, 86, 1131, -15.2249999999999996, -42.166400000000003, 'S 15 13 29', 'O 42 09 58', 152, 117);
INSERT INTO bdc.mux_grid VALUES ('152/118', '0106000020E610000001000000010300000001000000050000007F618A44F06345C010C9EF79382A2FC088F5A89D85EC44C0A0D6D039A5712FC0C39C7E97F30645C010544943CA9D30C0B908603E5E7E45C047CD58E3137A30C07F618A44F06345C010C9EF79382A2FC0', 87, 87, 1134, -16.1193999999999988, -42.3725000000000023, 'S 16 07 09', 'O 42 22 21', 152, 118);
INSERT INTO bdc.mux_grid VALUES ('152/119', '0106000020E610000001000000010300000001000000050000009B51066E657E45C0B1B52FBD117A30C064BA7A74010745C04AD4EF1DC69D30C011935C379A2145C0A66044C1B08231C0482AE830FE9845C00D428460FC5E31C09B51066E657E45C0B1B52FBD117A30C0', 88, 88, 1135, -17.0137, -42.5799999999999983, 'S 17 00 49', 'O 42 34 47', 152, 119);
INSERT INTO bdc.mux_grid VALUES ('152/120', '0106000020E610000001000000010300000001000000050000001FDC4EDE059945C0E7CABF14FA5E31C0BFE07905A92145C06551CE53AC8231C0778D90786F3C45C00E7FD834896732C0D6886551CCB345C08EF8C9F5D64332C01FDC4EDE059945C0E7CABF14FA5E31C0', 89, 89, 1136, -17.9076999999999984, -42.7888000000000019, 'S 17 54 27', 'O 42 47 19', 152, 120);
INSERT INTO bdc.mux_grid VALUES ('152/121', '0106000020E610000001000000010300000001000000050000002C28AF80D4B345C02B932D83D44332C06FD5CB3F7F3C45C0F45DE27C846732C0C282AA63765745C0316C7DDA524C33C07FD58DA4CBCE45C069A1C8E0A22833C02C28AF80D4B345C02B932D83D44332C0', 90, 90, 1137, -18.8016000000000005, -42.9990999999999985, 'S 18 48 05', 'O 42 59 56', 152, 121);
INSERT INTO bdc.mux_grid VALUES ('152/122', '0106000020E61000000100000001030000000100000005000000843B325AD4CE45C0473AFE45A02833C07470A42C875745C077B472D54D4C33C0E715531DB27245C009DF59EC0C3134C0F7E0E04AFFE945C0D964E55C5F0D34C0843B325AD4CE45C0473AFE45A02833C0', 91, 91, 1139, -19.6951000000000001, -43.2109999999999985, 'S 19 41 42', 'O 43 12 39', 152, 122);
INSERT INTO bdc.mux_grid VALUES ('152/123', '0106000020E610000001000000010300000001000000050000000BAAB28B08EA45C0D4C37B985C0D34C04D9D5AF1C37245C000ED7197073134C0CE0A82E8258E45C07A8E01A2B61535C08B17DA826A0546C04C650BA30BF234C00BAAB28B08EA45C0D4C37B985C0D34C0', 92, 92, 1140, -20.5884999999999998, -43.4245000000000019, 'S 20 35 18', 'O 43 25 28', 152, 123);
INSERT INTO bdc.mux_grid VALUES ('152/124', '0106000020E61000000100000001030000000100000005000000A3960C54740546C0046674B308F234C042D49FD1388E45C02C353CFAB01535C05DDCDA28D5A945C04CCB2C304FFA35C0BE9E47AB102146C024FC64E9A6D635C0A3960C54740546C0046674B308F234C0', 93, 93, 1141, -21.4816000000000003, -43.6396999999999977, 'S 21 28 53', 'O 43 38 22', 152, 124);
INSERT INTO bdc.mux_grid VALUES ('152/125', '0106000020E610000001000000010300000001000000050000004F6975121B2146C0CC98F3CCA3D635C05EC8DD31E9A945C05B964E3249FA35C0D7283365C3C545C0F51769C8D5DE36C0C7C9CA45F53C46C0671A0E6330BB36C04F6975121B2146C0CC98F3CCA3D635C0', 94, 94, 1142, -22.3744000000000014, -43.8567999999999998, 'S 22 22 27', 'O 43 51 24', 152, 125);
INSERT INTO bdc.mux_grid VALUES ('153/104', '0106000020E61000000100000001030000000100000005000000678992B2247944C0C561E99F0E5F08C00B1458D2850144C0E9B307913E7D09C098475AA6A51A44C0B9F04658275410C0F3BC9486449244C04D8F6FBF1E8A0FC0678992B2247944C0C561E99F0E5F08C0', 95, 95, 1225, -3.58429999999999982, -40.5322999999999993, 'S 03 35 03', 'O 40 31 56', 153, 104);
INSERT INTO bdc.mux_grid VALUES ('153/105', '0106000020E61000000100000001030000000100000005000000A2A9DCF1459244C06C274D5A1B8A0FC052C1257AA81A44C05CE973F6235410C04E4A944DD13344C025BDD50CA0E913C09E324BC56EAB44C0806788C3895A13C0A2A9DCF1459244C06C274D5A1B8A0FC0', 96, 96, 1226, -4.48029999999999973, -40.7287999999999997, 'S 04 28 49', 'O 40 43 43', 153, 105);
INSERT INTO bdc.mux_grid VALUES ('153/106', '0106000020E61000000100000001030000000100000005000000470C498F70AB44C0E185AB9F875A13C0422C3AD6D43344C0F636ABD29BE913C0B5A5D3CF084D44C0D8E66221097F17C0B985E288A4C444C0C33563EEF4EF16C0470C498F70AB44C0E185AB9F875A13C0', 97, 97, 1228, -5.37619999999999987, -40.9256000000000029, 'S 05 22 34', 'O 40 55 32', 153, 106);
INSERT INTO bdc.mux_grid VALUES ('153/107', '0106000020E61000000100000001030000000100000005000000B19C71B2A6C444C0FF4C3458F2EF16C0C0FE050F0D4D44C044A6D90C047F17C0390B0C5B4E6644C0D05CB3C45F141BC02AA977FEE7DD44C08A030E104E851AC0B19C71B2A6C444C0FF4C3458F2EF16C0', 98, 98, 1229, -6.27210000000000001, -41.122799999999998, 'S 06 16 19', 'O 41 07 22', 153, 107);
INSERT INTO bdc.mux_grid VALUES ('153/108', '0106000020E610000001000000010300000001000000050000007818A288EADD44C0E1C04E064B851AC04A8BD652536644C0AAEE58D359141BC0C8442724A47F44C07E28F423A1A91EC0F5D1F2593BF744C0B5FAE956921A1EC07818A288EADD44C0E1C04E064B851AC0', 99, 99, 1230, -7.16790000000000038, -41.3205000000000027, 'S 07 10 04', 'O 41 19 13', 153, 108);
INSERT INTO bdc.mux_grid VALUES ('153/109', '0106000020E610000001000000010300000001000000050000005693F2453EF744C0FBC722D88E1A1EC0035AF1D6A97F44C0BD5AE8529AA91EC042AC27680C9944C023B23835651F21C095E528D7A01045C0C0E8D577DFD720C05693F2453EF744C0FBC722D88E1A1EC0', 100, 100, 1233, -8.06359999999999921, -41.5185999999999993, 'S 08 03 49', 'O 41 31 07', 153, 109);
INSERT INTO bdc.mux_grid VALUES ('153/110', '0106000020E61000000100000001030000000100000005000000ED1A6926A41045C07F25157DDDD720C0E401B7D8129944C0DCA4315B611F21C0B329536D89B244C0938DA360ECE922C0BC4205BB1A2A45C0350E878268A222C0ED1A6926A41045C07F25157DDDD720C0', 101, 101, 1234, -8.95919999999999916, -41.7173999999999978, 'S 08 57 33', 'O 41 43 02', 153, 110);
INSERT INTO bdc.mux_grid VALUES ('153/111', '0106000020E61000000100000001030000000100000005000000EFB2236F1E2A45C0A8A4714B66A222C06D8ECE9E90B244C0B9C93813E8E922C0B40668841DCC44C0D88D85A764B424C0362BBD54AB4345C0C668BEDFE26C24C0EFB2236F1E2A45C0A8A4714B66A222C0', 102, 102, 1235, -9.85479999999999912, -41.9168999999999983, 'S 09 51 17', 'O 41 55 00', 153, 111);
INSERT INTO bdc.mux_grid VALUES ('153/112', '0106000020E61000000100000001030000000100000005000000E7F98B6FAF4345C0F28A3D6BE06C24C03EBE5A7A25CC44C0866D98E45FB424C097F5DC09CBE544C04173B79BCC7E26C03F310EFF545D45C0AD905C224D3726C0E7F98B6FAF4345C0F28A3D6BE06C24C0', 103, 103, 1236, -10.7501999999999995, -42.1169999999999973, 'S 10 45 00', 'O 42 07 01', 153, 112);
INSERT INTO bdc.mux_grid VALUES ('153/113', '0106000020E6100000010000000103000000010000000500000022D19582595D45C0F9F4386F4A3726C0F37C3AC8D3E544C01AFAEA60C77E26C0C4C02D6794FF44C0324D6CCD224928C0F41489211A7745C01248BADBA50128C022D19582595D45C0F9F4386F4A3726C0', 104, 104, 1237, -11.6454000000000004, -42.3179999999999978, 'S 11 38 43', 'O 42 19 04', 153, 113);
INSERT INTO bdc.mux_grid VALUES ('153/114', '0106000020E61000000100000001030000000100000005000000EB780A101F7745C0A3D99AE8A20128C0590A56F29DFF44C0F39F22181D4928C0942C36147C1945C009F4F8CA65132AC0269BEA31FD9045C0B92D719BEBCB29C0EB780A101F7745C0A3D99AE8A20128C0', 105, 105, 1239, -12.5404999999999998, -42.5198999999999998, 'S 12 32 25', 'O 42 31 11', 153, 114);
INSERT INTO bdc.mux_grid VALUES ('153/115', '0106000020E61000000100000001030000000100000005000000B3ABE18D029145C00394D966E8CB29C0275DFA70861945C0138350985F132AC05CB29C98843345C0CCF2952094DD2BC0E80084B500AB45C0BC031FEF1C962BC0B3ABE18D029145C00394D966E8CB29C0', 106, 106, 1240, -13.4354999999999993, -42.7227000000000032, 'S 13 26 07', 'O 42 43 21', 153, 115);
INSERT INTO bdc.mux_grid VALUES ('153/116', '0106000020E610000001000000010300000001000000050000009658AA8106AB45C090FF6D7719962BC0886744CC8F3345C06152666D8DDD2BC059D84E8DB04D45C0C9471B58ACA72DC066C9B44227C545C0FAF4226238602DC09658AA8106AB45C090FF6D7719962BC0', 107, 107, 1241, -14.3302999999999994, -42.9264999999999972, 'S 14 19 49', 'O 42 55 35', 153, 116);
INSERT INTO bdc.mux_grid VALUES ('153/117', '0106000020E610000001000000010300000001000000050000005DBE04822DC545C0688F90A534602DC082009E9DBC4D45C047B1F120A5A72DC0B20A119E026845C00D63B5F8AC712FC08EC8778273DF45C02E41547D3C2A2FC05DBE04822DC545C0688F90A534602DC0', 108, 108, 1242, -15.2249999999999996, -43.1315000000000026, 'S 15 13 29', 'O 43 07 53', 153, 117);
INSERT INTO bdc.mux_grid VALUES ('153/118', '0106000020E610000001000000010300000001000000050000003DC92F387ADF45C0CCC8EF79382A2FC0245D4E910F6845C070D6D039A5712FC05B04248B7D8245C0DB534943CA9D30C074700532E8F945C009CD58E3137A30C03DC92F387ADF45C0CCC8EF79382A2FC0', 109, 109, 1245, -16.1193999999999988, -43.3376999999999981, 'S 16 07 09', 'O 43 20 15', 153, 118);
INSERT INTO bdc.mux_grid VALUES ('153/119', '0106000020E6100000010000000103000000010000000500000023B9AB61EFF945C082B52FBD117A30C00E2220688B8245C010D4EF1DC69D30C0C5FA012B249D45C0BC6044C1B08231C0DA918D24881446C02D428460FC5E31C023B9AB61EFF945C082B52FBD117A30C0', 110, 110, 1246, -17.0137, -43.5450999999999979, 'S 17 00 49', 'O 43 32 42', 153, 119);
INSERT INTO bdc.mux_grid VALUES ('153/120', '0106000020E61000000100000001030000000100000005000000A643F4D18F1446C00BCBBF14FA5E31C069481FF9329D45C07E51CE53AC8231C021F5356CF9B745C0347FD834896732C05EF00A45562F46C0C1F8C9F5D64332C0A643F4D18F1446C00BCBBF14FA5E31C0', 111, 111, 1247, -17.9076999999999984, -43.7539999999999978, 'S 17 54 27', 'O 43 45 14', 153, 120);
INSERT INTO bdc.mux_grid VALUES ('153/121', '0106000020E61000000100000001030000000100000005000000C38F54745E2F46C058932D83D44332C0293D713309B845C0155EE27C846732C07EEA4F5700D345C0646C7DDA524C33C0183D3398554A46C0A7A1C8E0A22833C0C38F54745E2F46C058932D83D44332C0', 112, 112, 1249, -18.8016000000000005, -43.9643000000000015, 'S 18 48 05', 'O 43 57 51', 153, 121);
INSERT INTO bdc.mux_grid VALUES ('153/122', '0106000020E6100000010000000103000000010000000500000050A3D74D5E4A46C0753AFE45A02833C0FCD7492011D345C0B9B472D54D4C33C0687DF8103CEE45C01ADF59EC0C3134C0BD48863E896546C0D764E55C5F0D34C050A3D74D5E4A46C0753AFE45A02833C0', 113, 113, 1250, -19.6951000000000001, -44.1760999999999981, 'S 19 41 42', 'O 44 10 33', 153, 122);
INSERT INTO bdc.mux_grid VALUES ('153/123', '0106000020E610000001000000010300000001000000050000009811587F926546C0E3C37B985C0D34C0200500E54DEE45C0FAEC7197073134C0A27227DCAF0946C0838E01A2B61535C01A7F7F76F48046C06B650BA30BF234C09811587F926546C0E3C37B985C0D34C0', 114, 114, 1251, -20.5884999999999998, -44.3896000000000015, 'S 20 35 18', 'O 44 23 22', 153, 123);
INSERT INTO bdc.mux_grid VALUES ('153/124', '0106000020E6100000010000000103000000010000000500000057FEB147FE8046C0176674B308F234C0D33B45C5C20946C048353CFAB01535C0F043801C5F2546C077CB2C304FFA35C07306ED9E9A9C46C047FC64E9A6D635C057FEB147FE8046C0176674B308F234C0', 115, 115, 1252, -21.4816000000000003, -44.6049000000000007, 'S 21 28 53', 'O 44 36 17', 153, 124);
INSERT INTO bdc.mux_grid VALUES ('153/125', '0106000020E61000000100000001030000000100000005000000EAD01A06A59C46C0F798F3CCA3D635C0FB2F8325732546C084964E3249FA35C07490D8584D4146C02C1869C8D5DE36C0643170397FB846C0A11A0E6330BB36C0EAD01A06A59C46C0F798F3CCA3D635C0', 116, 116, 1253, -22.3744000000000014, -44.8220000000000027, 'S 22 22 27', 'O 44 49 19', 153, 125);
INSERT INTO bdc.mux_grid VALUES ('153/126', '0106000020E61000000100000001030000000100000005000000974AA23C8AB846C02647F4172DBB36C0CD74638D624146C0FB2FF770CFDE36C0767AEC3D7E5D46C0AA11C29849C337C040502BEDA5D446C0D428BF3FA79F37C0974AA23C8AB846C02647F4172DBB36C0', 117, 117, 1255, -23.2669999999999995, -45.0411000000000001, 'S 23 16 01', 'O 45 02 27', 153, 126);
INSERT INTO bdc.mux_grid VALUES ('154/104', '0106000020E610000001000000010300000001000000050000000CF137A6AEF444C04562E99F0E5F08C0AE7BFDC50F7D44C069B407913E7D09C037AFFF992F9644C099F04658275410C094243A7ACE0D45C00A8F6FBF1E8A0FC00CF137A6AEF444C04562E99F0E5F08C0', 118, 118, 1334, -3.58429999999999982, -41.4975000000000023, 'S 03 35 03', 'O 41 29 50', 154, 104);
INSERT INTO bdc.mux_grid VALUES ('154/105', '0106000020E61000000100000001030000000100000005000000461182E5CF0D45C023274D5A1B8A0FC0ED28CB6D329644C040E973F6235410C0EAB139415BAF44C048BDD50CA0E913C0439AF0B8F82645C09B6788C3895A13C0461182E5CF0D45C023274D5A1B8A0FC0', 119, 119, 1336, -4.48029999999999973, -41.6938999999999993, 'S 04 28 49', 'O 41 41 38', 154, 105);
INSERT INTO bdc.mux_grid VALUES ('154/106', '0106000020E61000000100000001030000000100000005000000E573EE82FA2645C00686AB9F875A13C0E993DFC95EAF44C01137ABD29BE913C05A0D79C392C844C0B2E66221097F17C057ED877C2E4045C0A73563EEF4EF16C0E573EE82FA2645C00686AB9F875A13C0', 120, 120, 1337, -5.37619999999999987, -41.8907000000000025, 'S 05 22 34', 'O 41 53 26', 154, 106);
INSERT INTO bdc.mux_grid VALUES ('154/107', '0106000020E61000000100000001030000000100000005000000590417A6304045C0D44C3458F2EF16C05766AB0297C844C030A6D90C047F17C0D072B14ED8E144C0BB5CB3C45F141BC0D2101DF2715945C05F030E104E851AC0590417A6304045C0D44C3458F2EF16C0', 121, 121, 1338, -6.27210000000000001, -42.0878999999999976, 'S 06 16 19', 'O 42 05 16', 154, 107);
INSERT INTO bdc.mux_grid VALUES ('154/108', '0106000020E610000001000000010300000001000000050000000680477C745945C0D5C04E064B851AC0FAF27B46DDE144C078EE58D359141BC074ACCC172EFB44C0CB27F423A1A91EC07F39984DC57245C029FAE956921A1EC00680477C745945C0D5C04E064B851AC0', 122, 122, 1339, -7.16790000000000038, -42.2856000000000023, 'S 07 10 04', 'O 42 17 08', 154, 108);
INSERT INTO bdc.mux_grid VALUES ('154/109', '0106000020E61000000100000001030000000100000005000000F4FA9739C87245C056C722D88E1A1EC090C196CA33FB44C02E5AE8529AA91EC0D513CD5B961445C05AB23835651F21C0394DCECA2A8C45C0EDE8D577DFD720C0F4FA9739C87245C056C722D88E1A1EC0', 123, 123, 1342, -8.06359999999999921, -42.4838000000000022, 'S 08 03 49', 'O 42 29 01', 154, 109);
INSERT INTO bdc.mux_grid VALUES ('154/110', '0106000020E6100000010000000103000000010000000500000093820E1A2E8C45C0AC25157DDDD720C09A695CCC9C1445C000A5315B611F21C06691F860132E45C0758DA360ECE922C05FAAAAAEA4A545C0230E878268A222C093820E1A2E8C45C0AC25157DDDD720C0', 124, 124, 1343, -8.95919999999999916, -42.6826000000000008, 'S 08 57 33', 'O 42 40 57', 154, 110);
INSERT INTO bdc.mux_grid VALUES ('154/111', '0106000020E610000001000000010300000001000000050000008E1AC962A8A545C098A4714B66A222C01DF673921A2E45C0A0C93813E8E922C0646E0D78A74745C0BD8D85A764B424C0D492624835BF45C0B668BEDFE26C24C08E1AC962A8A545C098A4714B66A222C0', 125, 125, 1344, -9.85479999999999912, -42.8819999999999979, 'S 09 51 17', 'O 42 52 55', 154, 111);
INSERT INTO bdc.mux_grid VALUES ('154/112', '0106000020E610000001000000010300000001000000050000008961316339BF45C0DF8A3D6BE06C24C0E125006EAF4745C0726D98E45FB424C0395D82FD546145C03073B79BCC7E26C0E198B3F2DED845C09B905C224D3726C08961316339BF45C0DF8A3D6BE06C24C0', 126, 126, 1345, -10.7501999999999995, -43.0822000000000003, 'S 10 45 00', 'O 43 04 55', 154, 112);
INSERT INTO bdc.mux_grid VALUES ('154/113', '0106000020E61000000100000001030000000100000005000000C2383B76E3D845C0E7F4386F4A3726C094E4DFBB5D6145C008FAEA60C77E26C06B28D35A1E7B45C0A24D6CCD224928C09B7C2E15A4F245C08248BADBA50128C0C2383B76E3D845C0E7F4386F4A3726C0', 127, 127, 1347, -11.6454000000000004, -43.2832000000000008, 'S 11 38 43', 'O 43 16 59', 154, 113);
INSERT INTO bdc.mux_grid VALUES ('154/114', '0106000020E610000001000000010300000001000000050000007FE0AF03A9F245C01EDA9AE8A20128C0EF71FBE5277B45C06DA022181D4928C03094DB07069545C0C2F4F8CA65132AC0BF029025870C46C0732E719BEBCB29C07FE0AF03A9F245C01EDA9AE8A20128C0', 128, 128, 1348, -12.5404999999999998, -43.4849999999999994, 'S 12 32 25', 'O 43 29 06', 154, 114);
INSERT INTO bdc.mux_grid VALUES ('154/115', '0106000020E61000000100000001030000000100000005000000641387818C0C46C0AF94D966E8CB29C0D6C49F64109545C0C08350985F132AC0FD19428C0EAF45C077F2952094DD2BC08B6829A98A2646C067031FEF1C962BC0641387818C0C46C0AF94D966E8CB29C0', 129, 129, 1349, -13.4354999999999993, -43.6878000000000029, 'S 13 26 07', 'O 43 41 16', 154, 115);
INSERT INTO bdc.mux_grid VALUES ('154/116', '0106000020E6100000010000000103000000010000000500000032C04F75902646C040FF6D7719962BC024CFE9BF19AF45C00E52666D8DDD2BC0FC3FF4803AC945C0F8471B58ACA72DC00A315A36B14046C028F5226238602DC032C04F75902646C040FF6D7719962BC0', 130, 130, 1350, -14.3302999999999994, -43.8917000000000002, 'S 14 19 49', 'O 43 53 30', 154, 116);
INSERT INTO bdc.mux_grid VALUES ('154/117', '0106000020E61000000100000001030000000100000005000000F825AA75B74046C09C8F90A534602DC04068439146C945C065B1F120A5A72DC06F72B6918CE345C02D63B5F8AC712FC027301D76FD5A46C06441547D3C2A2FC0F825AA75B74046C09C8F90A534602DC0', 131, 131, 1352, -15.2249999999999996, -44.0966999999999985, 'S 15 13 29', 'O 44 05 47', 154, 117);
INSERT INTO bdc.mux_grid VALUES ('154/118', '0106000020E61000000100000001030000000100000005000000BB30D52B045B46C012C9EF79382A2FC0E8C4F38499E345C08ED6D039A5712FC01E6CC97E07FE45C0EA534943CA9D30C0F2D7AA25727546C02DCD58E3137A30C0BB30D52B045B46C012C9EF79382A2FC0', 132, 132, 1354, -16.1193999999999988, -44.3027999999999977, 'S 16 07 09', 'O 44 18 10', 154, 118);
INSERT INTO bdc.mux_grid VALUES ('154/119', '0106000020E61000000100000001030000000100000005000000D6205155797546C096B52FBD117A30C09F89C55B15FE45C02FD4EF1DC69D30C05862A71EAE1846C0D96044C1B08231C08EF93218129046C041428460FC5E31C0D6205155797546C096B52FBD117A30C0', 133, 133, 1355, -17.0137, -44.5103000000000009, 'S 17 00 49', 'O 44 30 37', 154, 119);
INSERT INTO bdc.mux_grid VALUES ('154/120', '0106000020E6100000010000000103000000010000000500000050AB99C5199046C023CBBF14FA5E31C0EFAFC4ECBC1846C0A051CE53AC8231C0A15CDB5F833346C0167FD834896732C00158B038E0AA46C099F8C9F5D64332C050AB99C5199046C023CBBF14FA5E31C0', 134, 134, 1356, -17.9076999999999984, -44.7190999999999974, 'S 17 54 27', 'O 44 43 08', 154, 120);
INSERT INTO bdc.mux_grid VALUES ('154/121', '0106000020E6100000010000000103000000010000000500000050F7F967E8AA46C035932D83D44332C0B7A41627933346C0F25DE27C846732C00C52F54A8A4E46C0406C7DDA524C33C0A5A4D88BDFC546C083A1C8E0A22833C050F7F967E8AA46C035932D83D44332C0', 135, 135, 1357, -18.8016000000000005, -44.9294000000000011, 'S 18 48 05', 'O 44 55 45', 154, 121);
INSERT INTO bdc.mux_grid VALUES ('154/122', '0106000020E61000000100000001030000000100000005000000CD0A7D41E8C546C0573AFE45A02833C0BC3FEF139B4E46C086B472D54D4C33C032E59D04C66946C028DF59EC0C3134C042B02B3213E146C0F864E55C5F0D34C0CD0A7D41E8C546C0573AFE45A02833C0', 136, 136, 1358, -19.6951000000000001, -45.1413000000000011, 'S 19 41 42', 'O 45 08 28', 154, 122);
INSERT INTO bdc.mux_grid VALUES ('154/123', '0106000020E610000001000000010300000001000000050000004B79FD721CE146C0F7C37B985C0D34C0AF6CA5D8D76946C018ED7197073134C029DACCCF398546C0618E01A2B61535C0C4E6246A7EFC46C03F650BA30BF234C04B79FD721CE146C0F7C37B985C0D34C0', 137, 137, 1359, -20.5884999999999998, -45.3547999999999973, 'S 20 35 18', 'O 45 21 17', 154, 123);
INSERT INTO bdc.mux_grid VALUES ('154/124', '0106000020E610000001000000010300000001000000050000000366573B88FC46C0EB6574B308F234C07FA3EAB84C8546C01B353CFAB01535C0A3AB2510E9A046C08CCB2C304FFA35C0276E9292241847C05BFC64E9A6D635C00366573B88FC46C0EB6574B308F234C0', 138, 138, 1360, -21.4816000000000003, -45.5700000000000003, 'S 21 28 53', 'O 45 34 12', 154, 124);
INSERT INTO bdc.mux_grid VALUES ('154/125', '0106000020E61000000100000001030000000100000005000000A638C0F92E1847C00999F3CCA3D635C094972819FDA046C0A0964E3249FA35C0FFF77D4CD7BC46C0C71769C8D5DE36C01199152D093447C0311A0E6330BB36C0A638C0F92E1847C00999F3CCA3D635C0', 139, 139, 1362, -22.3744000000000014, -45.7871000000000024, 'S 22 22 27', 'O 45 47 13', 154, 125);
INSERT INTO bdc.mux_grid VALUES ('154/126', '0106000020E6100000010000000103000000010000000500000015B24730143447C0C646F4172DBB36C06DDC0881ECBC46C0902FF770CFDE36C016E2913108D946C03D11C29849C337C0C0B7D0E02F5047C07328BF3FA79F37C015B24730143447C0C646F4172DBB36C0', 140, 140, 1364, -23.2669999999999995, -46.0061999999999998, 'S 23 16 01', 'O 46 00 22', 154, 126);
INSERT INTO bdc.mux_grid VALUES ('155/104', '0106000020E61000000100000001030000000100000005000000AD58DD99387045C0F061E99F0E5F08C04FE3A2B999F844C014B407913E7D09C0DA16A58DB91145C0B3F04658275410C0378CDF6D588945C0448F6FBF1E8A0FC0AD58DD99387045C0F061E99F0E5F08C0', 141, 141, 1441, -3.58429999999999982, -42.4626000000000019, 'S 03 35 03', 'O 42 27 45', 155, 104);
INSERT INTO bdc.mux_grid VALUES ('155/105', '0106000020E61000000100000001030000000100000005000000E37827D9598945C06C274D5A1B8A0FC093907061BC1145C05BE973F6235410C09019DF34E52A45C03EBDD50CA0E913C0E00196AC82A245C0996788C3895A13C0E37827D9598945C06C274D5A1B8A0FC0', 142, 142, 1442, -4.48029999999999973, -42.6591000000000022, 'S 04 28 49', 'O 42 39 32', 155, 105);
INSERT INTO bdc.mux_grid VALUES ('155/106', '0106000020E610000001000000010300000001000000050000008BDB937684A245C0F885AB9F875A13C087FB84BDE82A45C00E37ABD29BE913C0FA741EB71C4445C0F4E66221097F17C0FF542D70B8BB45C0DE3563EEF4EF16C08BDB937684A245C0F885AB9F875A13C0', 143, 143, 1443, -5.37619999999999987, -42.8558999999999983, 'S 05 22 34', 'O 42 51 21', 155, 106);
INSERT INTO bdc.mux_grid VALUES ('155/107', '0106000020E61000000100000001030000000100000005000000FD6BBC99BABB45C0144D3458F2EF16C003CE50F6204445C063A6D90C047F17C079DA5642625D45C0B55CB3C45F141BC07278C2E5FBD445C065030E104E851AC0FD6BBC99BABB45C0144D3458F2EF16C0', 144, 144, 1444, -6.27210000000000001, -43.0531000000000006, 'S 06 16 19', 'O 43 03 11', 155, 107);
INSERT INTO bdc.mux_grid VALUES ('155/108', '0106000020E61000000100000001030000000100000005000000B7E7EC6FFED445C0C6C04E064B851AC0885A213A675D45C090EE58D359141BC00414720BB87645C02C28F423A1A91EC033A13D414FEE45C061FAE956921A1EC0B7E7EC6FFED445C0C6C04E064B851AC0', 145, 145, 1446, -7.16790000000000038, -43.2507999999999981, 'S 07 10 04', 'O 43 15 02', 155, 108);
INSERT INTO bdc.mux_grid VALUES ('155/109', '0106000020E61000000100000001030000000100000005000000AB623D2D52EE45C086C722D88E1A1EC035293CBEBD7645C0745AE8529AA91EC0787B724F209045C04AB23835651F21C0EFB473BEB40746C0D3E8D577DFD720C0AB623D2D52EE45C086C722D88E1A1EC0', 146, 146, 1448, -8.06359999999999921, -43.4489000000000019, 'S 08 03 49', 'O 43 26 56', 155, 109);
INSERT INTO bdc.mux_grid VALUES ('155/110', '0106000020E6100000010000000103000000010000000500000023EAB30DB80746C0A625157DDDD720C03DD101C0269045C0EEA4315B611F21C00AF99D549DA945C0878DA360ECE922C0F21150A22E2146C03F0E878268A222C023EAB30DB80746C0A625157DDDD720C0', 147, 147, 1449, -8.95919999999999916, -43.6477000000000004, 'S 08 57 33', 'O 43 38 51', 155, 110);
INSERT INTO bdc.mux_grid VALUES ('155/111', '0106000020E610000001000000010300000001000000050000002D826E56322146C0ADA4714B66A222C0BD5D1986A4A945C0B3C93813E8E922C002D6B26B31C345C0B38D85A764B424C072FA073CBF3A46C0AC68BEDFE26C24C02D826E56322146C0ADA4714B66A222C0', 148, 148, 1450, -9.85479999999999912, -43.8470999999999975, 'S 09 51 17', 'O 43 50 49', 155, 111);
INSERT INTO bdc.mux_grid VALUES ('155/112', '0106000020E610000001000000010300000001000000050000002EC9D656C33A46C0D38A3D6BE06C24C0858DA56139C345C0666D98E45FB424C0DFC427F1DEDC45C04473B79BCC7E26C0870059E6685446C0B2905C224D3726C02EC9D656C33A46C0D38A3D6BE06C24C0', 149, 149, 1452, -10.7501999999999995, -44.0472999999999999, 'S 10 45 00', 'O 44 02 50', 155, 112);
INSERT INTO bdc.mux_grid VALUES ('155/113', '0106000020E6100000010000000103000000010000000500000053A0E0696D5446C00BF5386F4A3726C0364C85AFE7DC45C020FAEA60C77E26C00B90784EA8F645C09C4D6CCD224928C029E4D3082E6E46C08648BADBA50128C053A0E0696D5446C00BF5386F4A3726C0', 150, 150, 1453, -11.6454000000000004, -44.2483000000000004, 'S 11 38 43', 'O 44 14 53', 155, 113);
INSERT INTO bdc.mux_grid VALUES ('155/114', '0106000020E61000000100000001030000000100000005000000324855F7326E46C00EDA9AE8A20128C07DD9A0D9B1F645C073A022181D4928C0BBFB80FB8F1046C0AAF4F8CA65132AC06E6A3519118846C0462E719BEBCB29C0324855F7326E46C00EDA9AE8A20128C0', 151, 151, 1454, -12.5404999999999998, -44.4502000000000024, 'S 12 32 25', 'O 44 27 00', 155, 114);
INSERT INTO bdc.mux_grid VALUES ('155/115', '0106000020E61000000100000001030000000100000005000000087B2C75168846C08B94D966E8CB29C07C2C45589A1046C09A8350985F132AC0A881E77F982A46C0B5F2952094DD2BC034D0CE9C14A246C0A5031FEF1C962BC0087B2C75168846C08B94D966E8CB29C0', 152, 152, 1455, -13.4354999999999993, -44.6529999999999987, 'S 13 26 07', 'O 44 39 10', 155, 115);
INSERT INTO bdc.mux_grid VALUES ('155/116', '0106000020E61000000100000001030000000100000005000000D727F5681AA246C07EFF6D7719962BC0C8368FB3A32A46C04D52666D8DDD2BC09EA79974C44446C01A481B58ACA72DC0AD98FF293BBC46C04AF5226238602DC0D727F5681AA246C07EFF6D7719962BC0', 153, 153, 1457, -14.3302999999999994, -44.8567999999999998, 'S 14 19 49', 'O 44 51 24', 155, 116);
INSERT INTO bdc.mux_grid VALUES ('155/117', '0106000020E61000000100000001030000000100000005000000928D4F6941BC46C0C38F90A534602DC0D9CFE884D04446C08FB1F120A5A72DC008DA5B85165F46C03663B5F8AC712FC0C097C26987D646C06C41547D3C2A2FC0928D4F6941BC46C0C38F90A534602DC0', 154, 154, 1458, -15.2249999999999996, -45.0617999999999981, 'S 15 13 29', 'O 45 03 42', 155, 117);
INSERT INTO bdc.mux_grid VALUES ('155/118', '0106000020E610000001000000010300000001000000050000007B987A1F8ED646C002C9EF79382A2FC0632C9978235F46C0A5D6D039A5712FC09DD36E72917946C00F544943CA9D30C0B53F5019FCF046C03CCD58E3137A30C07B987A1F8ED646C002C9EF79382A2FC0', 155, 155, 1460, -16.1193999999999988, -45.2680000000000007, 'S 16 07 09', 'O 45 16 04', 155, 118);
INSERT INTO bdc.mux_grid VALUES ('155/119', '0106000020E610000001000000010300000001000000050000008A88F64803F146C0AAB52FBD117A30C054F16A4F9F7946C044D4EF1DC69D30C002CA4C12389446C09F6044C1B08231C03961D80B9C0B47C006428460FC5E31C08A88F64803F146C0AAB52FBD117A30C0', 156, 156, 1461, -17.0137, -45.4754000000000005, 'S 17 00 49', 'O 45 28 31', 155, 119);
INSERT INTO bdc.mux_grid VALUES ('155/120', '0106000020E61000000100000001030000000100000005000000EF123FB9A30B47C0EBCABF14FA5E31C08F176AE0469446C06951CE53AC8231C04FC480530DAF46C0507FD834896732C0ADBF552C6A2647C0D2F8C9F5D64332C0EF123FB9A30B47C0EBCABF14FA5E31C0', 157, 157, 1463, -17.9076999999999984, -45.6843000000000004, 'S 17 54 27', 'O 45 41 03', 155, 120);
INSERT INTO bdc.mux_grid VALUES ('155/121', '0106000020E610000001000000010300000001000000050000000D5F9F5B722647C06A932D83D44332C0500CBC1A1DAF46C0345EE27C846732C09DB99A3E14CA46C0326C7DDA524C33C0590C7E7F694147C069A1C8E0A22833C00D5F9F5B722647C06A932D83D44332C0', 158, 158, 1464, -18.8016000000000005, -45.894599999999997, 'S 18 48 05', 'O 45 53 40', 155, 121);
INSERT INTO bdc.mux_grid VALUES ('155/122', '0106000020E610000001000000010300000001000000050000006E722235724147C0413AFE45A02833C03CA7940725CA46C07CB472D54D4C33C0A74C43F84FE546C0CFDE59EC0C3134C0D917D1259D5C47C09364E55C5F0D34C06E722235724147C0413AFE45A02833C0', 159, 159, 1465, -19.6951000000000001, -46.1064000000000007, 'S 19 41 42', 'O 46 06 23', 155, 122);
INSERT INTO bdc.mux_grid VALUES ('155/123', '0106000020E61000000100000001030000000100000005000000C9E0A266A65C47C09AC37B985C0D34C051D44ACC61E546C0B3EC7197073134C0D84172C3C30047C06B8E01A2B61535C0514ECA5D087847C053650BA30BF234C0C9E0A266A65C47C09AC37B985C0D34C0', 160, 160, 1466, -20.5884999999999998, -46.319899999999997, 'S 20 35 18', 'O 46 19 11', 155, 123);
INSERT INTO bdc.mux_grid VALUES ('155/124', '0106000020E6100000010000000103000000010000000500000092CDFC2E127847C0FF6574B308F234C0310B90ACD60047C026353CFAB01535C05B13CB03731C47C0C7CB2C304FFA35C0BCD53786AE9347C09FFC64E9A6D635C092CDFC2E127847C0FF6574B308F234C0', 161, 161, 1468, -21.4816000000000003, -46.5352000000000032, 'S 21 28 53', 'O 46 32 06', 155, 124);
INSERT INTO bdc.mux_grid VALUES ('155/125', '0106000020E6100000010000000103000000010000000500000045A065EDB89347C04999F3CCA3D635C055FFCD0C871C47C0D7964E3249FA35C0C65F2340613847C0321869C8D5DE36C0B600BB2093AF47C0A41A0E6330BB36C045A065EDB89347C04999F3CCA3D635C0', 162, 162, 1469, -22.3744000000000014, -46.7522999999999982, 'S 22 22 27', 'O 46 45 08', 155, 125);
INSERT INTO bdc.mux_grid VALUES ('155/126', '0106000020E61000000100000001030000000100000005000000AD19ED239EAF47C03A47F4172DBB36C00644AE74763847C00830F770CFDE36C0B0493725925447C0A511C29849C337C0561F76D4B9CB47C0DA28BF3FA79F37C0AD19ED239EAF47C03A47F4172DBB36C0', 163, 163, 1471, -23.2669999999999995, -46.9714000000000027, 'S 23 16 01', 'O 46 58 16', 155, 126);
INSERT INTO bdc.mux_grid VALUES ('155/127', '0106000020E6100000010000000103000000010000000500000094D82B7AC5CB47C0DA770BC4A39F37C0B200D091A85447C06DBAFDE342C337C0344A9088097147C0C2F961CBA9A738C01722EC7026E847C02FB76FAB0A8438C094D82B7AC5CB47C0DA770BC4A39F37C0', 164, 164, 1473, -24.1593000000000018, -47.1925000000000026, 'S 24 09 33', 'O 47 11 33', 155, 127);
INSERT INTO bdc.mux_grid VALUES ('156/103', '0106000020E6100000010000000103000000010000000500000098325E89A8D245C0BBFB01ADEE3301C0DAE81796085B45C0B9A42930215202C0E60DFD8C217445C005F83AA7437D09C0A4574380C1EB45C0064F1324115F08C098325E89A8D245C0BBFB01ADEE3301C0', 165, 165, 1551, -2.68829999999999991, -43.2314999999999969, 'S 02 41 17', 'O 43 13 53', 156, 103);
INSERT INTO bdc.mux_grid VALUES ('156/104', '0106000020E610000001000000010300000001000000050000004FC0828DC2EB45C03B62E99F0E5F08C0F14A48AD237445C061B407913E7D09C07B7E4A81438D45C093F04658275410C0D8F38461E20446C0018F6FBF1E8A0FC04FC0828DC2EB45C03B62E99F0E5F08C0', 166, 166, 1552, -3.58429999999999982, -43.4277000000000015, 'S 03 35 03', 'O 43 25 39', 156, 104);
INSERT INTO bdc.mux_grid VALUES ('156/105', '0106000020E6100000010000000103000000010000000500000088E0CCCCE30446C023274D5A1B8A0FC030F81555468D45C040E973F6235410C02B8184286FA645C04BBDD50CA0E913C085693BA00C1E46C09C6788C3895A13C088E0CCCCE30446C023274D5A1B8A0FC0', 167, 167, 1553, -4.48029999999999973, -43.6242000000000019, 'S 04 28 49', 'O 43 37 27', 156, 105);
INSERT INTO bdc.mux_grid VALUES ('156/106', '0106000020E610000001000000010300000001000000050000002943396A0E1E46C00286AB9F875A13C02E632AB172A645C00E37ABD29BE913C0A0DCC3AAA6BF45C0AFE66221097F17C09BBCD263423746C0A43563EEF4EF16C02943396A0E1E46C00286AB9F875A13C0', 168, 168, 1554, -5.37619999999999987, -43.820999999999998, 'S 05 22 34', 'O 43 49 15', 156, 106);
INSERT INTO bdc.mux_grid VALUES ('156/107', '0106000020E610000001000000010300000001000000050000009AD3618D443746C0D64C3458F2EF16C0A035F6E9AABF45C027A6D90C047F17C01B42FC35ECD845C0F35CB3C45F141BC015E067D9855046C0A3030E104E851AC09AD3618D443746C0D64C3458F2EF16C0', 169, 169, 1556, -6.27210000000000001, -44.0182000000000002, 'S 06 16 19', 'O 44 01 05', 156, 107);
INSERT INTO bdc.mux_grid VALUES ('156/108', '0106000020E61000000100000001030000000100000005000000464F9263885046C01BC14E064B851AC03BC2C62DF1D845C0BCEE58D359141BC0B57B17FF41F245C01128F423A1A91EC0C008E334D96946C06FFAE956921A1EC0464F9263885046C01BC14E064B851AC0', 170, 170, 1557, -7.16790000000000038, -44.2158999999999978, 'S 07 10 04', 'O 44 12 57', 156, 108);
INSERT INTO bdc.mux_grid VALUES ('156/109', '0106000020E610000001000000010300000001000000050000004ECAE220DC6946C07CC722D88E1A1EC0E990E1B147F245C0545AE8529AA91EC02AE31743AA0B46C02BB23835651F21C08F1C19B23E8346C0BEE8D577DFD720C04ECAE220DC6946C07CC722D88E1A1EC0', 171, 171, 1559, -8.06359999999999921, -44.4140999999999977, 'S 08 03 49', 'O 44 24 50', 156, 109);
INSERT INTO bdc.mux_grid VALUES ('156/110', '0106000020E61000000100000001030000000100000005000000D7515901428346C08725157DDDD720C0CD38A7B3B00B46C0E5A4315B611F21C098604348272546C05D8DA360ECE922C0A279F595B89C46C0FF0D878268A222C0D7515901428346C08725157DDDD720C0', 172, 172, 1560, -8.95919999999999916, -44.6129000000000033, 'S 08 57 33', 'O 44 36 46', 156, 110);
INSERT INTO bdc.mux_grid VALUES ('156/111', '0106000020E61000000100000001030000000100000005000000B8E9134ABC9C46C083A4714B66A222C059C5BE792E2546C07FC93813E8E922C0A33D585FBB3E46C0DD8D85A764B424C00262AD2F49B646C0E168BEDFE26C24C0B8E9134ABC9C46C083A4714B66A222C0', 173, 173, 1562, -9.85479999999999912, -44.8123000000000005, 'S 09 51 17', 'O 44 48 44', 156, 111);
INSERT INTO bdc.mux_grid VALUES ('156/112', '0106000020E61000000100000001030000000100000005000000D3307C4A4DB646C0FB8A3D6BE06C24C02AF54A55C33E46C08D6D98E45FB424C0842CCDE4685846C04873B79BCC7E26C02B68FED9F2CF46C0B6905C224D3726C0D3307C4A4DB646C0FB8A3D6BE06C24C0', 174, 174, 1563, -10.7501999999999995, -45.0125000000000028, 'S 10 45 00', 'O 45 00 44', 156, 112);
INSERT INTO bdc.mux_grid VALUES ('156/113', '0106000020E610000001000000010300000001000000050000001708865DF7CF46C0FBF4386F4A3726C0C6B32AA3715846C030FAEA60C77E26C09AF71D42327246C08C4D6CCD224928C0EB4B79FCB7E946C05548BADBA50128C01708865DF7CF46C0FBF4386F4A3726C0', 175, 175, 1564, -11.6454000000000004, -45.2134, 'S 11 38 43', 'O 45 12 48', 156, 113);
INSERT INTO bdc.mux_grid VALUES ('156/114', '0106000020E61000000100000001030000000100000005000000E2AFFAEABCE946C0E6D99AE8A20128C02F4146CD3B7246C04BA022181D4928C06D6326EF198C46C0A2F4F8CA65132AC020D2DA0C9B0347C03D2E719BEBCB29C0E2AFFAEABCE946C0E6D99AE8A20128C0', 176, 176, 1565, -12.5404999999999998, -45.415300000000002, 'S 12 32 25', 'O 45 24 55', 156, 114);
INSERT INTO bdc.mux_grid VALUES ('156/115', '0106000020E610000001000000010300000001000000050000008CE2D168A00347C09B94D966E8CB29C02294EA4B248C46C0978350985F132AC050E98C7322A646C0CFF2952094DD2BC0BA3774909E1D47C0D3031FEF1C962BC08CE2D168A00347C09B94D966E8CB29C0', 177, 177, 1567, -13.4354999999999993, -45.6180999999999983, 'S 13 26 07', 'O 45 37 05', 156, 115);
INSERT INTO bdc.mux_grid VALUES ('156/116', '0106000020E610000001000000010300000001000000050000007A8F9A5CA41D47C09BFF6D7719962BC06C9E34A72DA646C06C52666D8DDD2BC03C0F3F684EC046C0D8471B58ACA72DC04A00A51DC53747C006F5226238602DC07A8F9A5CA41D47C09BFF6D7719962BC0', 178, 178, 1568, -14.3302999999999994, -45.8220000000000027, 'S 14 19 49', 'O 45 49 19', 156, 116);
INSERT INTO bdc.mux_grid VALUES ('156/117', '0106000020E6100000010000000103000000010000000500000048F5F45CCB3747C06F8F90A534602DC06D378E785AC046C04EB1F120A5A72DC09D410179A0DA46C01463B5F8AC712FC078FF675D115247C03541547D3C2A2FC048F5F45CCB3747C06F8F90A534602DC0', 179, 179, 1569, -15.2249999999999996, -46.027000000000001, 'S 15 13 29', 'O 46 01 37', 156, 117);
INSERT INTO bdc.mux_grid VALUES ('156/118', '0106000020E6100000010000000103000000010000000500000019002013185247C0DCC8EF79382A2FC022943E6CADDA46C06CD6D039A5712FC0593B14661BF546C0DC534943CA9D30C04FA7F50C866C47C015CD58E3137A30C019002013185247C0DCC8EF79382A2FC0', 180, 180, 1571, -16.1193999999999988, -46.2331000000000003, 'S 16 07 09', 'O 46 13 59', 156, 118);
INSERT INTO bdc.mux_grid VALUES ('156/119', '0106000020E6100000010000000103000000010000000500000014F09B3C8D6C47C087B52FBD117A30C00159104329F546C015D4EF1DC69D30C0B031F205C20F47C0806044C1B08231C0C3C87DFF258747C0F2418460FC5E31C014F09B3C8D6C47C087B52FBD117A30C0', 181, 181, 1573, -17.0137, -46.4406000000000034, 'S 17 00 49', 'O 46 26 26', 156, 119);
INSERT INTO bdc.mux_grid VALUES ('156/120', '0106000020E61000000100000001030000000100000005000000937AE4AC2D8747C0D2CABF14FA5E31C0347F0FD4D00F47C04D51CE53AC8231C0EB2B2647972A47C0047FD834896732C04B27FB1FF4A147C087F8C9F5D64332C0937AE4AC2D8747C0D2CABF14FA5E31C0', 182, 182, 1574, -17.9076999999999984, -46.6494, 'S 17 54 27', 'O 46 38 57', 156, 120);
INSERT INTO bdc.mux_grid VALUES ('156/121', '0106000020E6100000010000000103000000010000000500000098C6444FFCA147C024932D83D44332C0FC73610EA72A47C0E15DE27C846732C0592140329E4547C06F6C7DDA524C33C0F3732373F3BC47C0B3A1C8E0A22833C098C6444FFCA147C024932D83D44332C0', 183, 183, 1575, -18.8016000000000005, -46.8596999999999966, 'S 18 48 05', 'O 46 51 34', 156, 121);
INSERT INTO bdc.mux_grid VALUES ('156/122', '0106000020E610000001000000010300000001000000050000003CDAC728FCBC47C07C3AFE45A02833C0E80E3AFBAE4547C0BFB472D54D4C33C04DB4E8EBD96047C0E1DE59EC0C3134C0A27F761927D847C09E64E55C5F0D34C03CDAC728FCBC47C07C3AFE45A02833C0', 184, 184, 1576, -19.6951000000000001, -47.0715000000000003, 'S 19 41 42', 'O 47 04 17', 156, 122);
INSERT INTO bdc.mux_grid VALUES ('156/123', '0106000020E610000001000000010300000001000000050000007A48485A30D847C0A9C37B985C0D34C0DE3BF0BFEB6047C0CBEC7197073134C069A917B74D7C47C0938E01A2B61535C004B66F5192F347C072650BA30BF234C07A48485A30D847C0A9C37B985C0D34C0', 185, 185, 1578, -20.5884999999999998, -47.2849999999999966, 'S 20 35 18', 'O 47 17 06', 156, 123);
INSERT INTO bdc.mux_grid VALUES ('156/124', '0106000020E610000001000000010300000001000000050000002335A2229CF347C0296674B308F234C0C37235A0607C47C04F353CFAB01535C0EF7A70F7FC9747C0FDCB2C304FFA35C04F3DDD79380F48C0D6FC64E9A6D635C02335A2229CF347C0296674B308F234C0', 186, 186, 1579, -21.4816000000000003, -47.5003000000000029, 'S 21 28 53', 'O 47 30 01', 156, 124);
INSERT INTO bdc.mux_grid VALUES ('156/125', '0106000020E61000000100000001030000000100000005000000BF070BE1420F48C08999F3CCA3D635C0F2667300119847C00B974E3249FA35C056C7C833EBB347C0F51769C8D5DE36C0226860141D2B48C0731A0E6330BB36C0BF070BE1420F48C08999F3CCA3D635C0', 187, 187, 1580, -22.3744000000000014, -47.7173999999999978, 'S 22 22 27', 'O 47 43 02', 156, 125);
INSERT INTO bdc.mux_grid VALUES ('156/126', '0106000020E6100000010000000103000000010000000500000075819217282B48C0EF46F4172DBB36C089AB536800B447C0CE2FF770CFDE36C033B1DC181CD047C07B11C29849C337C01F871BC8434748C09E28BF3FA79F37C075819217282B48C0EF46F4172DBB36C0', 188, 188, 1583, -23.2669999999999995, -47.9365000000000023, 'S 23 16 01', 'O 47 56 11', 156, 126);
INSERT INTO bdc.mux_grid VALUES ('156/127', '0106000020E610000001000000010300000001000000050000002240D16D4F4748C0B0770BC4A39F37C08568758532D047C02DBAFDE342C337C007B2357C93EC47C092F961CBA9A738C0A4899164B06348C015B76FAB0A8438C02240D16D4F4748C0B0770BC4A39F37C0', 189, 189, 1584, -24.1593000000000018, -48.1576999999999984, 'S 24 09 33', 'O 48 09 27', 156, 127);
INSERT INTO bdc.mux_grid VALUES ('156/128', '0106000020E610000001000000010300000001000000050000001E26C9B3BC6348C07DC40AFD068438C0AFA0552EABEC47C056A243B5A2A738C0D4D5485F550948C0AE122986F58B39C0445BBCE4668048C0D534F0CD596839C01E26C9B3BC6348C07DC40AFD068438C0', 190, 190, 1585, -25.0512000000000015, -48.3811000000000035, 'S 25 03 04', 'O 48 22 51', 156, 128);
INSERT INTO bdc.mux_grid VALUES ('156/129', '0106000020E61000000100000001030000000100000005000000AF8FFCE4738048C0A0CE99EA556839C08A0F6F656E0948C074E85A0AEE8B39C0F9E3D1F2652648C0D8EF3AEA2B703AC01E645F726B9D48C001D679CA934C3AC0AF8FFCE4738048C0A0CE99EA556839C0', 191, 191, 1586, -25.9429000000000016, -48.6067999999999998, 'S 25 56 34', 'O 48 36 24', 156, 129);
INSERT INTO bdc.mux_grid VALUES ('156/130', '0106000020E61000000100000001030000000100000005000000A1C2C12B799D48C067DEC5AF8F4C3AC07A14975C802648C023E9120424703AC0A77C719AC94348C000BF80134C543BC0CE2A9C69C2BA48C044B433BFB7303BC0A1C2C12B799D48C067DEC5AF8F4C3AC0', 192, 192, 1588, -26.8341999999999992, -48.8348999999999975, 'S 26 50 03', 'O 48 50 05', 156, 130);
INSERT INTO bdc.mux_grid VALUES ('156/131', '0106000020E61000000100000001030000000100000005000000FB9BD8E4D0BA48C05AB3866AB3303BC03CC89D78E54348C0FB10FABD43543BC077EC94F0846148C072891F1855383CC037C0CF5C70D848C0D02BACC4C4143CC0FB9BD8E4D0BA48C05AB3866AB3303BC0', 193, 193, 1589, -27.7251000000000012, -49.0656999999999996, 'S 27 43 30', 'O 49 03 56', 156, 131);
INSERT INTO bdc.mux_grid VALUES ('156/132', '0106000020E61000000100000001030000000100000005000000341E49A37FD848C0758A3733C0143CC0C9FF3755A26148C0D275D34D4C383CC06C2CAFCA9C7F48C0372BE107461C3DC0D84AC0187AF648C0DB3F45EDB9F83CC0341E49A37FD848C0758A3733C0143CC0', 194, 194, 1590, -28.6157000000000004, -49.299199999999999, 'S 28 36 56', 'O 49 17 57', 156, 132);
INSERT INTO bdc.mux_grid VALUES ('157/103', '0106000020E610000001000000010300000001000000050000003C9A037D324E46C0B1FB01ADEE3301C07C50BD8992D645C0B2A42930215202C08875A280ABEF45C0BEF73AA7437D09C047BFE8734B6746C0BC4E1324115F08C03C9A037D324E46C0B1FB01ADEE3301C0', 195, 195, 1661, -2.68829999999999991, -44.1966999999999999, 'S 02 41 17', 'O 44 11 48', 157, 103);
INSERT INTO bdc.mux_grid VALUES ('157/104', '0106000020E61000000100000001030000000100000005000000EF2728814C6746C0F861E99F0E5F08C093B2EDA0ADEF45C01DB407913E7D09C01FE6EF74CD0846C0B3F04658275410C07A5B2A556C8046C0408F6FBF1E8A0FC0EF2728814C6746C0F861E99F0E5F08C0', 196, 196, 1662, -3.58429999999999982, -44.3928999999999974, 'S 03 35 03', 'O 44 23 34', 157, 104);
INSERT INTO bdc.mux_grid VALUES ('157/105', '0106000020E610000001000000010300000001000000050000002D4872C06D8046C053274D5A1B8A0FC0D55FBB48D00846C05BE973F6235410C0CFE8291CF92146C026BDD50CA0E913C028D1E093969946C0796788C3895A13C02D4872C06D8046C053274D5A1B8A0FC0', 197, 197, 1663, -4.48029999999999973, -44.5893999999999977, 'S 04 28 49', 'O 44 35 21', 157, 105);
INSERT INTO bdc.mux_grid VALUES ('157/106', '0106000020E61000000100000001030000000100000005000000D0AADE5D989946C0DC85AB9F875A13C0CACACFA4FC2146C0F236ABD29BE913C03F44699E303B46C014E76221097F17C045247857CCB246C0FE3563EEF4EF16C0D0AADE5D989946C0DC85AB9F875A13C0', 198, 198, 1665, -5.37619999999999987, -44.7862000000000009, 'S 05 22 34', 'O 44 47 10', 157, 106);
INSERT INTO bdc.mux_grid VALUES ('157/107', '0106000020E61000000100000001030000000100000005000000463B0781CEB246C02C4D3458F2EF16C0449D9BDD343B46C088A6D90C047F17C0BBA9A129765446C0D55CB3C45F141BC0BD470DCD0FCC46C079030E104E851AC0463B0781CEB246C02C4D3458F2EF16C0', 199, 199, 1666, -6.27210000000000001, -44.9834000000000032, 'S 06 16 19', 'O 44 59 00', 157, 107);
INSERT INTO bdc.mux_grid VALUES ('157/108', '0106000020E61000000100000001030000000100000005000000F5B6375712CC46C0E7C04E064B851AC0C7296C217B5446C0B1EE58D359141BC042E3BCF2CB6D46C00428F423A1A91EC07070882863E546C03BFAE956921A1EC0F5B6375712CC46C0E7C04E064B851AC0', 200, 200, 1667, -7.16790000000000038, -45.1809999999999974, 'S 07 10 04', 'O 45 10 51', 157, 108);
INSERT INTO bdc.mux_grid VALUES ('157/109', '0106000020E61000000100000001030000000100000005000000F231881466E546C05AC722D88E1A1EC08CF886A5D16D46C0325AE8529AA91EC0CD4ABD36348746C019B23835651F21C03284BEA5C8FE46C0ADE8D577DFD720C0F231881466E546C05AC722D88E1A1EC0', 201, 201, 1669, -8.06359999999999921, -45.3791999999999973, 'S 08 03 49', 'O 45 22 45', 157, 109);
INSERT INTO bdc.mux_grid VALUES ('157/110', '0106000020E6100000010000000103000000010000000500000079B9FEF4CBFE46C07425157DDDD720C081A04CA73A8746C0C9A4315B611F21C04CC8E83BB1A046C0408DA360ECE922C044E19A89421847C0EB0D878268A222C079B9FEF4CBFE46C07425157DDDD720C0', 202, 202, 1671, -8.95919999999999916, -45.578000000000003, 'S 08 57 33', 'O 45 34 40', 157, 110);
INSERT INTO bdc.mux_grid VALUES ('157/111', '0106000020E610000001000000010300000001000000050000006751B93D461847C069A4714B66A222C0E52C646DB8A046C07BC93813E8E922C030A5FD5245BA46C0D98D85A764B424C0B2C95223D33147C0C768BEDFE26C24C06751B93D461847C069A4714B66A222C0', 203, 203, 1672, -9.85479999999999912, -45.7774000000000001, 'S 09 51 17', 'O 45 46 38', 157, 111);
INSERT INTO bdc.mux_grid VALUES ('157/112', '0106000020E610000001000000010300000001000000050000007598213ED73147C0E68A3D6BE06C24C0CD5CF0484DBA46C07B6D98E45FB424C0269472D8F2D346C03673B79BCC7E26C0CDCFA3CD7C4B47C0A3905C224D3726C07598213ED73147C0E68A3D6BE06C24C0', 204, 204, 1673, -10.7501999999999995, -45.9776000000000025, 'S 10 45 00', 'O 45 58 39', 157, 112);
INSERT INTO bdc.mux_grid VALUES ('157/113', '0106000020E61000000100000001030000000100000005000000B86F2B51814B47C0EAF4386F4A3726C0881BD096FBD346C00AFAEA60C77E26C0595FC335BCED46C0254D6CCD224928C089B31EF0416547C00448BADBA50128C0B86F2B51814B47C0EAF4386F4A3726C0', 205, 205, 1674, -11.6454000000000004, -46.178600000000003, 'S 11 38 43', 'O 46 10 42', 157, 113);
INSERT INTO bdc.mux_grid VALUES ('157/114', '0106000020E610000001000000010300000001000000050000006D17A0DE466547C0A0D99AE8A20128C0DBA8EBC0C5ED46C0F09F22181D4928C023CBCBE2A30747C0C7F4F8CA65132AC0B3398000257F47C0772E719BEBCB29C06D17A0DE466547C0A0D99AE8A20128C0', 206, 206, 1676, -12.5404999999999998, -46.3804999999999978, 'S 12 32 25', 'O 46 22 49', 157, 114);
INSERT INTO bdc.mux_grid VALUES ('157/115', '0106000020E61000000100000001030000000100000005000000354A775C2A7F47C0C894D966E8CB29C0A7FB8F3FAE0747C0D88350985F132AC0CE503267AC2147C090F2952094DD2BC05C9F1984289947C080031FEF1C962BC0354A775C2A7F47C0C894D966E8CB29C0', 207, 207, 1677, -13.4354999999999993, -46.5833000000000013, 'S 13 26 07', 'O 46 34 59', 157, 115);
INSERT INTO bdc.mux_grid VALUES ('157/116', '0106000020E6100000010000000103000000010000000500000016F73F502E9947C04DFF6D7719962BC00906DA9AB72147C01B52666D8DDD2BC0E076E45BD83B47C006481B58ACA72DC0EE674A114FB347C037F5226238602DC016F73F502E9947C04DFF6D7719962BC0', 208, 208, 1678, -14.3302999999999994, -46.7871000000000024, 'S 14 19 49', 'O 46 47 13', 157, 116);
INSERT INTO bdc.mux_grid VALUES ('157/117', '0106000020E61000000100000001030000000100000005000000E35C9A5055B347C0A38F90A534602DC02B9F336CE43B47C06DB1F120A5A72DC05AA9A66C2A5647C03663B5F8AC712FC012670D519BCD47C06B41547D3C2A2FC0E35C9A5055B347C0A38F90A534602DC0', 209, 209, 1679, -15.2249999999999996, -46.9921000000000006, 'S 15 13 29', 'O 46 59 31', 157, 117);
INSERT INTO bdc.mux_grid VALUES ('157/118', '0106000020E610000001000000010300000001000000050000009667C506A2CD47C022C9EF79382A2FC0C3FBE35F375647C09CD6D039A5712FC0FAA2B959A57047C0F5534943CA9D30C0CD0E9B0010E847C039CD58E3137A30C09667C506A2CD47C022C9EF79382A2FC0', 210, 210, 1682, -16.1193999999999988, -47.1983000000000033, 'S 16 07 09', 'O 47 11 53', 157, 118);
INSERT INTO bdc.mux_grid VALUES ('157/119', '0106000020E61000000100000001030000000100000005000000A557413017E847C0A5B52FBD117A30C091C0B536B37047C033D4EF1DC69D30C0429997F94B8B47C09E6044C1B08231C0563023F3AF0248C010428460FC5E31C0A557413017E847C0A5B52FBD117A30C0', 211, 211, 1683, -17.0137, -47.4057000000000031, 'S 17 00 49', 'O 47 24 20', 157, 119);
INSERT INTO bdc.mux_grid VALUES ('157/120', '0106000020E610000001000000010300000001000000050000003CE289A0B70248C0E7CABF14FA5E31C0DCE6B4C75A8B47C06451CE53AC8231C09C93CB3A21A647C05B7FD834896732C0FC8EA0137E1D48C0DFF8C9F5D64332C03CE289A0B70248C0E7CABF14FA5E31C0', 212, 212, 1684, -17.9076999999999984, -47.6146000000000029, 'S 17 54 27', 'O 47 36 52', 157, 120);
INSERT INTO bdc.mux_grid VALUES ('157/121', '0106000020E61000000100000001030000000100000005000000352EEA42861D48C081932D83D44332C09BDB060231A647C03F5EE27C846732C0E888E52528C147C04C6C7DDA524C33C082DBC8667D3848C08FA1C8E0A22833C0352EEA42861D48C081932D83D44332C0', 213, 213, 1685, -18.8016000000000005, -47.8248000000000033, 'S 18 48 05', 'O 47 49 29', 157, 121);
INSERT INTO bdc.mux_grid VALUES ('157/122', '0106000020E61000000100000001030000000100000005000000B9416D1C863848C05E3AFE45A02833C0A976DFEE38C147C08DB472D54D4C33C0161C8EDF63DC47C0EEDE59EC0C3134C025E71B0DB15348C0BF64E55C5F0D34C0B9416D1C863848C05E3AFE45A02833C0', 214, 214, 1687, -19.6951000000000001, -48.0367000000000033, 'S 19 41 42', 'O 48 02 12', 157, 122);
INSERT INTO bdc.mux_grid VALUES ('157/123', '0106000020E610000001000000010300000001000000050000002BB0ED4DBA5348C0BFC37B985C0D34C090A395B375DC47C0E0EC7197073134C01B11BDAAD7F747C0A98E01A2B61535C0B51D15451C6F48C087650BA30BF234C02BB0ED4DBA5348C0BFC37B985C0D34C0', 215, 215, 1688, -20.5884999999999998, -48.2501999999999995, 'S 20 35 18', 'O 48 15 00', 157, 123);
INSERT INTO bdc.mux_grid VALUES ('157/124', '0106000020E61000000100000001030000000100000005000000FA9C4716266F48C0326674B308F234C054DADA93EAF747C06C353CFAB01535C070E215EB861348C09CCB2C304FFA35C015A5826DC28A48C061FC64E9A6D635C0FA9C4716266F48C0326674B308F234C0', 216, 216, 1689, -21.4816000000000003, -48.4654999999999987, 'S 21 28 53', 'O 48 27 55', 157, 124);
INSERT INTO bdc.mux_grid VALUES ('157/125', '0106000020E61000000100000001030000000100000005000000B16FB0D4CC8A48C00699F3CCA3D635C05ACE18F49A1348C0B1964E3249FA35C0CD2E6E27752F48C01A1869C8D5DE36C024D00508A7A648C06F1A0E6330BB36C0B16FB0D4CC8A48C00699F3CCA3D635C0', 217, 217, 1690, -22.3744000000000014, -48.6826000000000008, 'S 22 22 27', 'O 48 40 57', 157, 125);
INSERT INTO bdc.mux_grid VALUES ('157/126', '0106000020E6100000010000000103000000010000000500000004E9370BB2A648C00D47F4172DBB36C05B13F95B8A2F48C0D82FF770CFDE36C0F618820CA64B48C00611C29849C337C09EEEC0BBCDC248C03B28BF3FA79F37C004E9370BB2A648C00D47F4172DBB36C0', 218, 218, 1693, -23.2669999999999995, -48.9016999999999982, 'S 23 16 01', 'O 48 54 05', 157, 126);
INSERT INTO bdc.mux_grid VALUES ('157/127', '0106000020E61000000100000001030000000100000005000000A5A77661D9C248C04E770BC4A39F37C007D01A79BC4B48C0CBB9FDE342C337C09A19DB6F1D6848C0AFF961CBA9A738C037F136583ADF48C032B76FAB0A8438C0A5A77661D9C248C04E770BC4A39F37C0', 219, 219, 1694, -24.1593000000000018, -49.122799999999998, 'S 24 09 33', 'O 49 07 22', 157, 127);
INSERT INTO bdc.mux_grid VALUES ('157/128', '0106000020E610000001000000010300000001000000050000009E8D6EA746DF48C0A0C40AFD068438C07408FB21356848C064A243B5A2A738C0993DEE52DF8448C0BC122986F58B39C0C4C261D8F0FB48C0F834F0CD596839C09E8D6EA746DF48C0A0C40AFD068438C0', 220, 220, 1695, -25.0512000000000015, -49.3462000000000032, 'S 25 03 04', 'O 49 20 46', 157, 128);
INSERT INTO bdc.mux_grid VALUES ('157/129', '0106000020E6100000010000000103000000010000000500000033F7A1D8FDFB48C0C2CE99EA556839C098771459F88448C06DE85A0AEE8B39C0064C77E6EFA148C0CFEF3AEA2B703AC0A1CB0466F51849C023D679CA934C3AC033F7A1D8FDFB48C0C2CE99EA556839C0', 221, 221, 1697, -25.9429000000000016, -49.5718999999999994, 'S 25 56 34', 'O 49 34 18', 157, 129);
INSERT INTO bdc.mux_grid VALUES ('157/130', '0106000020E61000000100000001030000000100000005000000352A671F031949C084DEC5AF8F4C3AC00F7C3C500AA248C03FE9120424703AC02CE4168E53BF48C09DBE80134C543BC05392415D4C3649C0E2B333BFB7303BC0352A671F031949C084DEC5AF8F4C3AC0', 222, 222, 1698, -26.8341999999999992, -49.8001000000000005, 'S 26 50 03', 'O 49 48 00', 157, 130);
INSERT INTO bdc.mux_grid VALUES ('157/131', '0106000020E61000000100000001030000000100000005000000AE037ED85A3649C0EAB2866AB3303BC0A82F436C6FBF48C0A110FABD43543BC0F5533AE40EDD48C097891F1855383CC0FB277550FA5349C0E02BACC4C4143CC0AE037ED85A3649C0EAB2866AB3303BC0', 223, 223, 1699, -27.7251000000000012, -50.0307999999999993, 'S 27 43 30', 'O 50 01 50', 157, 131);
INSERT INTO bdc.mux_grid VALUES ('157/132', '0106000020E61000000100000001030000000100000005000000FE85EE96095449C0818A3733C0143CC04D67DD482CDD48C0F375D34D4C383CC0F19354BE26FB48C0592BE107461C3DC0A0B2650C047249C0E93F45EDB9F83CC0FE85EE96095449C0818A3733C0143CC0', 224, 224, 1700, -28.6157000000000004, -50.2642999999999986, 'S 28 36 56', 'O 50 15 51', 157, 132);
INSERT INTO bdc.mux_grid VALUES ('157/133', '0106000020E610000001000000010300000001000000050000001FAD3728147249C05520031CB5F83CC0671BE0BC45FB48C02516FFC23C1C3DC05DBF7031A01949C001BB8EEB1D003EC01351C89C6E9049C031C5924496DC3DC01FAD3728147249C05520031CB5F83CC0', 225, 225, 1702, -29.5060000000000002, -50.5007000000000019, 'S 29 30 21', 'O 50 30 02', 157, 133);
INSERT INTO bdc.mux_grid VALUES ('158/102', '0106000020E610000001000000010300000001000000050000006EC43A88A7B046C0EDBC373A8211F4BF82E8DCD6063946C053261ACEEA4DF6BF2A0D940F1B5246C01B5B579B245202C016E9F1C0BBC946C06A266651F03301C06EC43A88A7B046C0EDBC373A8211F4BF', 226, 226, 1771, -1.79220000000000002, -44.9658000000000015, 'S 01 47 31', 'O 44 57 56', 158, 102);
INSERT INTO bdc.mux_grid VALUES ('158/103', '0106000020E61000000100000001030000000100000005000000E401A970BCC946C0D6FB01ADEE3301C020B8627D1C5246C0E0A42930215202C02ADD4774356B46C0B6F73AA7437D09C0EF268E67D5E246C0AC4E1324115F08C0E401A970BCC946C0D6FB01ADEE3301C0', 227, 227, 1772, -2.68829999999999991, -45.1617999999999995, 'S 02 41 17', 'O 45 09 42', 158, 103);
INSERT INTO bdc.mux_grid VALUES ('158/104', '0106000020E61000000100000001030000000100000005000000918FCD74D6E246C0F061E99F0E5F08C0341A9394376B46C015B407913E7D09C0BF4D9568578446C0B4F04658275410C01CC3CF48F6FB46C0448F6FBF1E8A0FC0918FCD74D6E246C0F061E99F0E5F08C0', 228, 228, 1773, -3.58429999999999982, -45.357999999999997, 'S 03 35 03', 'O 45 21 28', 158, 104);
INSERT INTO bdc.mux_grid VALUES ('158/105', '0106000020E61000000100000001030000000100000005000000D2AF17B4F7FB46C057274D5A1B8A0FC079C7603C5A8446C05BE973F6235410C07650CF0F839D46C03DBDD50CA0E913C0CF388687201547C08E6788C3895A13C0D2AF17B4F7FB46C057274D5A1B8A0FC0', 229, 229, 1775, -4.48029999999999973, -45.5544999999999973, 'S 04 28 49', 'O 45 33 16', 158, 105);
INSERT INTO bdc.mux_grid VALUES ('158/106', '0106000020E6100000010000000103000000010000000500000070128451221547C0FD85AB9F875A13C072327598869D46C00A37ABD29BE913C0E7AB0E92BAB646C02FE76221097F17C0E38B1D4B562E47C0243663EEF4EF16C070128451221547C0FD85AB9F875A13C0', 230, 230, 1776, -5.37619999999999987, -45.7513000000000005, 'S 05 22 34', 'O 45 45 04', 158, 106);
INSERT INTO bdc.mux_grid VALUES ('158/107', '0106000020E61000000100000001030000000100000005000000DEA2AC74582E47C0584D3458F2EF16C0ED0441D1BEB646C09FA6D90C047F17C06211471D00D046C0B05CB3C45F141BC053AFB2C0994747C06A030E104E851AC0DEA2AC74582E47C0584D3458F2EF16C0', 231, 231, 1777, -6.27210000000000001, -45.9485000000000028, 'S 06 16 19', 'O 45 56 54', 158, 107);
INSERT INTO bdc.mux_grid VALUES ('158/108', '0106000020E61000000100000001030000000100000005000000941EDD4A9C4747C0D0C04E064B851AC07891111505D046C085EE58D359141BC0F44A62E655E946C01D28F423A1A91EC011D82D1CED6047C068FAE956921A1EC0941EDD4A9C4747C0D0C04E064B851AC0', 232, 232, 1778, -7.16790000000000038, -46.1462000000000003, 'S 07 10 04', 'O 46 08 46', 158, 108);
INSERT INTO bdc.mux_grid VALUES ('158/109', '0106000020E6100000010000000103000000010000000500000095992D08F06047C083C722D88E1A1EC031602C995BE946C05B5AE8529AA91EC073B2622ABE0247C03DB23835651F21C0D8EB6399527A47C0D1E8D577DFD720C095992D08F06047C083C722D88E1A1EC0', 233, 233, 1781, -8.06359999999999921, -46.3444000000000003, 'S 08 03 49', 'O 46 20 39', 158, 109);
INSERT INTO bdc.mux_grid VALUES ('158/110', '0106000020E610000001000000010300000001000000050000000E21A4E8557A47C0A325157DDDD720C02808F29AC40247C0ECA4315B611F21C0F02F8E2F3B1C47C0458DA360ECE922C0D848407DCC9347C0FD0D878268A222C00E21A4E8557A47C0A325157DDDD720C0', 234, 234, 1782, -8.95919999999999916, -46.5431999999999988, 'S 08 57 33', 'O 46 32 35', 158, 110);
INSERT INTO bdc.mux_grid VALUES ('158/111', '0106000020E6100000010000000103000000010000000500000007B95E31D09347C072A4714B66A222C097940961421C47C079C93813E8E922C0DE0CA346CF3547C0B78D85A764B424C05031F8165DAD47C0B268BEDFE26C24C007B95E31D09347C072A4714B66A222C0', 235, 235, 1783, -9.85479999999999912, -46.742600000000003, 'S 09 51 17', 'O 46 44 33', 158, 111);
INSERT INTO bdc.mux_grid VALUES ('158/112', '0106000020E610000001000000010300000001000000050000001800C73161AD47C0CF8A3D6BE06C24C070C4953CD73547C0636D98E45FB424C0CAFB17CC7C4F47C04173B79BCC7E26C0733749C106C747C0AD905C224D3726C01800C73161AD47C0CF8A3D6BE06C24C0', 236, 236, 1784, -10.7501999999999995, -46.9427999999999983, 'S 10 45 00', 'O 46 56 33', 158, 112);
INSERT INTO bdc.mux_grid VALUES ('158/113', '0106000020E610000001000000010300000001000000050000005AD7D0440BC747C0F7F4386F4A3726C02A83758A854F47C017FAEA60C77E26C000C76829466947C0934D6CCD224928C0301BC4E3CBE047C07248BADBA50128C05AD7D0440BC747C0F7F4386F4A3726C0', 237, 237, 1785, -11.6454000000000004, -47.1437000000000026, 'S 11 38 43', 'O 47 08 37', 158, 113);
INSERT INTO bdc.mux_grid VALUES ('158/114', '0106000020E61000000100000001030000000100000005000000247F45D2D0E047C005DA9AE8A20128C0711091B44F6947C069A022181D4928C0AF3271D62D8347C0A2F4F8CA65132AC062A125F4AEFA47C03F2E719BEBCB29C0247F45D2D0E047C005DA9AE8A20128C0', 238, 238, 1786, -12.5404999999999998, -47.3455999999999975, 'S 12 32 25', 'O 47 20 44', 158, 114);
INSERT INTO bdc.mux_grid VALUES ('158/115', '0106000020E61000000100000001030000000100000005000000DAB11C50B4FA47C09694D966E8CB29C04C633533388347C0A58350985F132AC07AB8D75A369D47C0C1F2952094DD2BC00607BF77B21448C0B3031FEF1C962BC0DAB11C50B4FA47C09694D966E8CB29C0', 239, 239, 1787, -13.4354999999999993, -47.5484000000000009, 'S 13 26 07', 'O 47 32 54', 158, 115);
INSERT INTO bdc.mux_grid VALUES ('158/116', '0106000020E61000000100000001030000000100000005000000965EE543B81448C095FF6D7719962BC0AB6D7F8E419D47C05052666D8DDD2BC082DE894F62B747C01A481B58ACA72DC06CCFEF04D92E48C060F5226238602DC0965EE543B81448C095FF6D7719962BC0', 240, 240, 1788, -14.3302999999999994, -47.7522999999999982, 'S 14 19 49', 'O 47 45 08', 158, 116);
INSERT INTO bdc.mux_grid VALUES ('158/117', '0106000020E610000001000000010300000001000000050000007CC43F44DF2E48C0BF8F90A534602DC0C506D95F6EB747C089B1F120A5A72DC0F1104C60B4D147C03563B5F8AC712FC0AACEB244254948C06B41547D3C2A2FC07CC43F44DF2E48C0BF8F90A534602DC0', 241, 241, 1789, -15.2249999999999996, -47.9572999999999965, 'S 15 13 29', 'O 47 57 26', 158, 117);
INSERT INTO bdc.mux_grid VALUES ('158/118', '0106000020E6100000010000000103000000010000000500000055CF6AFA2B4948C009C9EF79382A2FC03C638953C1D147C0ACD6D039A5712FC0770A5F4D2FEC47C010544943CA9D30C08F7640F4996348C03DCD58E3137A30C055CF6AFA2B4948C009C9EF79382A2FC0', 242, 242, 1792, -16.1193999999999988, -48.1634000000000029, 'S 16 07 09', 'O 48 09 48', 158, 118);
INSERT INTO bdc.mux_grid VALUES ('158/119', '0106000020E610000001000000010300000001000000050000007BBFE623A16348C0A5B52FBD117A30C021285B2A3DEC47C049D4EF1DC69D30C0D0003DEDD50648C0A46044C1B08231C02A98C8E6397E48C000428460FC5E31C07BBFE623A16348C0A5B52FBD117A30C0', 243, 243, 1793, -17.0137, -48.3708999999999989, 'S 17 00 49', 'O 48 22 15', 158, 119);
INSERT INTO bdc.mux_grid VALUES ('158/120', '0106000020E61000000100000001030000000100000005000000E1492F94417E48C0E4CABF14FA5E31C0814E5ABBE40648C06351CE53AC8231C040FB702EAB2148C04A7FD834896732C09FF64507089948C0CBF8C9F5D64332C0E1492F94417E48C0E4CABF14FA5E31C0', 244, 244, 1794, -17.9076999999999984, -48.5797000000000025, 'S 17 54 27', 'O 48 34 46', 158, 120);
INSERT INTO bdc.mux_grid VALUES ('158/121', '0106000020E61000000100000001030000000100000005000000E7958F36109948C06C932D83D44332C02A43ACF5BA2148C0345EE27C846732C076F08A19B23C48C0326C7DDA524C33C033436E5A07B448C06AA1C8E0A22833C0E7958F36109948C06C932D83D44332C0', 245, 245, 1796, -18.8016000000000005, -48.7899999999999991, 'S 18 48 05', 'O 48 47 23', 158, 121);
INSERT INTO bdc.mux_grid VALUES ('158/122', '0106000020E6100000010000000103000000010000000500000058A9121010B448C03E3AFE45A02833C026DE84E2C23C48C078B472D54D4C33C0998333D3ED5748C00ADF59EC0C3134C0CB4EC1003BCF48C0D064E55C5F0D34C058A9121010B448C03E3AFE45A02833C0', 246, 246, 1797, -19.6951000000000001, -49.0018000000000029, 'S 19 41 42', 'O 49 00 06', 158, 122);
INSERT INTO bdc.mux_grid VALUES ('158/123', '0106000020E61000000100000001030000000100000005000000DC17934144CF48C0CCC37B985C0D34C0400B3BA7FF5748C0F0EC7197073134C0C178629E617348C0688E01A2B61535C05C85BA38A6EA48C044650BA30BF234C0DC17934144CF48C0CCC37B985C0D34C0', 247, 247, 1798, -20.5884999999999998, -49.2152999999999992, 'S 20 35 18', 'O 49 12 55', 158, 123);
INSERT INTO bdc.mux_grid VALUES ('158/124', '0106000020E610000001000000010300000001000000050000008004ED09B0EA48C0F96574B308F234C01F428087747348C020353CFAB01535C0414ABBDE108F48C081CB2C304FFA35C0A30C28614C0649C059FC64E9A6D635C08004ED09B0EA48C0F96574B308F234C0', 248, 248, 1799, -21.4816000000000003, -49.4305999999999983, 'S 21 28 53', 'O 49 25 50', 158, 124);
INSERT INTO bdc.mux_grid VALUES ('158/125', '0106000020E6100000010000000103000000010000000500000025D755C8560649C00899F3CCA3D635C05736BEE7248F48C08A964E3249FA35C0C796131BFFAA48C0E31769C8D5DE36C09537ABFB302249C0601A0E6330BB36C025D755C8560649C00899F3CCA3D635C0', 249, 249, 1801, -22.3744000000000014, -49.6477000000000004, 'S 22 22 27', 'O 49 38 51', 158, 125);
INSERT INTO bdc.mux_grid VALUES ('158/126', '0106000020E61000000100000001030000000100000005000000D150DDFE3B2249C0E346F4172DBB36C0E47A9E4F14AB48C0C42FF770CFDE36C08D80270030C748C06211C29849C337C0785666AF573E49C08228BF3FA79F37C0D150DDFE3B2249C0E346F4172DBB36C0', 250, 250, 1803, -23.2669999999999995, -49.8667999999999978, 'S 23 16 01', 'O 49 52 00', 158, 126);
INSERT INTO bdc.mux_grid VALUES ('158/127', '0106000020E610000001000000010300000001000000050000003F0F1C55633E49C0A6770BC4A39F37C0A237C06C46C748C025BAFDE342C337C032818063A7E348C0FAF961CBA9A738C0D058DC4BC45A49C07BB76FAB0A8438C03F0F1C55633E49C0A6770BC4A39F37C0', 251, 251, 1804, -24.1593000000000018, -50.088000000000001, 'S 24 09 33', 'O 50 05 16', 158, 127);
INSERT INTO bdc.mux_grid VALUES ('158/128', '0106000020E6100000010000000103000000010000000500000069F5139BD05A49C0DBC40AFD068438C0F86FA015BFE348C0B4A243B5A2A738C01CA59346690049C0FE122986F58B39C08D2A07CC7A7749C02435F0CD596839C069F5139BD05A49C0DBC40AFD068438C0', 252, 252, 1805, -25.0512000000000015, -50.311399999999999, 'S 25 03 04', 'O 50 18 40', 158, 128);
INSERT INTO bdc.mux_grid VALUES ('158/129', '0106000020E61000000100000001030000000100000005000000BB5E47CC877749C002CF99EA556839C020DFB94C820049C0B0E85A0AEE8B39C07CB31CDA791D49C082EF3AEA2B703AC01733AA597F9449C0D5D579CA934C3AC0BB5E47CC877749C002CF99EA556839C0', 253, 253, 1806, -25.9429000000000016, -50.5371000000000024, 'S 25 56 34', 'O 50 32 13', 158, 129);
INSERT INTO bdc.mux_grid VALUES ('158/130', '0106000020E6100000010000000103000000010000000500000001920C138D9449C01ADEC5AF8F4C3AC094E3E143941D49C0ECE8120424703AC0D14BBC81DD3A49C03BBF80134C543BC03DFAE650D6B149C06AB433BFB7303BC001920C138D9449C01ADEC5AF8F4C3AC0', 254, 254, 1807, -26.8341999999999992, -50.7652000000000001, 'S 26 50 03', 'O 50 45 54', 158, 130);
INSERT INTO bdc.mux_grid VALUES ('158/131', '0106000020E610000001000000010300000001000000050000003C6B23CCE4B149C08AB3866AB3303BC07B97E85FF93A49C02D11FABD43543BC0B5BBDFD7985849C095891F1855383CC0768F1A4484CF49C0F12BACC4C4143CC03C6B23CCE4B149C08AB3866AB3303BC0', 255, 255, 1808, -27.7251000000000012, -50.9960000000000022, 'S 27 43 30', 'O 50 59 45', 158, 131);
INSERT INTO bdc.mux_grid VALUES ('158/132', '0106000020E610000001000000010300000001000000050000007FED938A93CF49C0938A3733C0143CC014CF823CB65849C0F275D34D4C383CC0B5FBF9B1B07649C0492BE107461C3DC0211A0B008EED49C0EB3F45EDB9F83CC07FED938A93CF49C0938A3733C0143CC0', 256, 256, 1810, -28.6157000000000004, -51.2295000000000016, 'S 28 36 56', 'O 51 13 46', 158, 132);
INSERT INTO bdc.mux_grid VALUES ('158/133', '0106000020E61000000100000001030000000100000005000000EE14DD1B9EED49C04120031CB5F83CC0F18285B0CF7649C02716FFC23C1C3DC0E52616252A9549C0F4BA8EEB1D003EC0E1B86D90F80B4AC00DC5924496DC3DC0EE14DD1B9EED49C04120031CB5F83CC0', 257, 257, 1811, -29.5060000000000002, -51.4658999999999978, 'S 29 30 21', 'O 51 27 57', 158, 133);
INSERT INTO bdc.mux_grid VALUES ('158/134', '0106000020E61000000100000001030000000100000005000000BA227C8C090C4AC0406F413091DC3DC069F37AD24A9549C04F73D32514003EC028A6CC8A0AB449C0D9EC3AC4DBE33EC077D5CD44C92A4AC0CAE8A8CE58C03EC0BA227C8C090C4AC0406F413091DC3DC0', 258, 258, 1812, -30.3958000000000013, -51.7053000000000011, 'S 30 23 44', 'O 51 42 19', 158, 134);
INSERT INTO bdc.mux_grid VALUES ('158/135', '0106000020E610000001000000010300000001000000050000007D86D52CDB2A4AC002BEC57353C03EC06CCE9AFD2CB449C03211E776D1E33EC07B5DA58657D349C0D3CA7A8A7EC73FC08A15E0B5054A4AC0A477598700A43FC07D86D52CDB2A4AC002BEC57353C03EC0', 259, 259, 1815, -31.2852999999999994, -51.9480000000000004, 'S 31 17 06', 'O 51 56 52', 158, 135);
INSERT INTO bdc.mux_grid VALUES ('159/102', '0106000020E61000000100000001030000000100000005000000112CE07B312C47C0FDBC373A8211F4BF225082CA90B446C069261ACEEA4DF6BFCA743903A5CD46C0225B579B245202C0B95097B4454547C06A266651F03301C0112CE07B312C47C0FDBC373A8211F4BF', 260, 260, 1884, -1.79220000000000002, -45.9309000000000012, 'S 01 47 31', 'O 45 55 51', 159, 102);
INSERT INTO bdc.mux_grid VALUES ('159/103', '0106000020E6100000010000000103000000010000000500000082694E64464547C0E2FB01ADEE3301C0C81F0871A6CD46C0D6A42930215202C0D244ED67BFE646C0A3F73AA7437D09C08E8E335B5F5E47C0AE4E1324115F08C082694E64464547C0E2FB01ADEE3301C0', 261, 261, 1885, -2.68829999999999991, -46.1270000000000024, 'S 02 41 17', 'O 46 07 37', 159, 103);
INSERT INTO bdc.mux_grid VALUES ('159/104', '0106000020E6100000010000000103000000010000000500000033F77268605E47C0ED61E99F0E5F08C0D7813888C1E646C014B407913E7D09C05FB53A5CE1FF46C06DF04658275410C0BB2A753C807747C0B38E6FBF1E8A0FC033F77268605E47C0ED61E99F0E5F08C0', 262, 262, 1886, -3.58429999999999982, -46.3231999999999999, 'S 03 35 03', 'O 46 19 23', 159, 104);
INSERT INTO bdc.mux_grid VALUES ('159/105', '0106000020E610000001000000010300000001000000050000007517BDA7817747C0BF264D5A1B8A0FC01D2F0630E4FF46C00FE973F6235410C019B874030D1947C01CBDD50CA0E913C073A02B7BAA9047C06D6788C3895A13C07517BDA7817747C0BF264D5A1B8A0FC0', 263, 263, 1887, -4.48029999999999973, -46.5197000000000003, 'S 04 28 49', 'O 46 31 10', 159, 105);
INSERT INTO bdc.mux_grid VALUES ('159/106', '0106000020E610000001000000010300000001000000050000000B7A2945AC9047C0E385AB9F875A13C00F9A1A8C101947C0EE36ABD29BE913C08613B485443247C050E76221097F17C081F3C23EE0A947C0453663EEF4EF16C00B7A2945AC9047C0E385AB9F875A13C0', 264, 264, 1888, -5.37619999999999987, -46.7165000000000035, 'S 05 22 34', 'O 46 42 59', 159, 106);
INSERT INTO bdc.mux_grid VALUES ('159/107', '0106000020E61000000100000001030000000100000005000000880A5268E2A947C06D4D3458F2EF16C0866CE6C4483247C0C8A6D90C047F17C0FC78EC108A4B47C0155DB3C45F141BC0FF1658B423C347C0BA030E104E851AC0880A5268E2A947C06D4D3458F2EF16C0', 265, 265, 1889, -6.27210000000000001, -46.9136999999999986, 'S 06 16 19', 'O 46 54 49', 159, 107);
INSERT INTO bdc.mux_grid VALUES ('159/108', '0106000020E610000001000000010300000001000000050000003586823E26C347C02AC14E064B851AC01AF9B6088F4B47C0E0EE58D359141BC093B207DADF6447C03528F423A1A91EC0AF3FD30F77DC47C07DFAE956921A1EC03586823E26C347C02AC14E064B851AC0', 266, 266, 1890, -7.16790000000000038, -47.1113, 'S 07 10 04', 'O 47 06 40', 159, 108);
INSERT INTO bdc.mux_grid VALUES ('159/109', '0106000020E610000001000000010300000001000000050000003801D3FB79DC47C095C722D88E1A1EC0D3C7D18CE56447C06B5AE8529AA91EC0151A081E487E47C034B23835651F21C07A53098DDCF547C0C8E8D577DFD720C03801D3FB79DC47C095C722D88E1A1EC0', 267, 267, 1893, -8.06359999999999921, -47.3094999999999999, 'S 08 03 49', 'O 47 18 34', 159, 109);
INSERT INTO bdc.mux_grid VALUES ('159/110', '0106000020E61000000100000001030000000100000005000000C18849DCDFF547C09025157DDDD720C0B76F978E4E7E47C0EEA4315B611F21C083973323C59747C0668DA360ECE922C08DB0E570560F48C0080E878268A222C0C18849DCDFF547C09025157DDDD720C0', 268, 268, 1894, -8.95919999999999916, -47.5082999999999984, 'S 08 57 33', 'O 47 30 29', 159, 110);
INSERT INTO bdc.mux_grid VALUES ('159/111', '0106000020E61000000100000001030000000100000005000000A62004255A0F48C089A4714B66A222C036FCAE54CC9747C090C93813E8E922C08174483A59B147C0ED8D85A764B424C0F1989D0AE72848C0E668BEDFE26C24C0A62004255A0F48C089A4714B66A222C0', 269, 269, 1895, -9.85479999999999912, -47.7077000000000027, 'S 09 51 17', 'O 47 42 27', 159, 111);
INSERT INTO bdc.mux_grid VALUES ('159/112', '0106000020E61000000100000001030000000100000005000000C0676C25EB2848C0018B3D6BE06C24C0182C3B3061B147C0966D98E45FB424C06C63BDBF06CB47C01073B79BCC7E26C0159FEEB4904248C07E905C224D3726C0C0676C25EB2848C0018B3D6BE06C24C0', 270, 270, 1896, -10.7501999999999995, -47.9078999999999979, 'S 10 45 00', 'O 47 54 28', 159, 112);
INSERT INTO bdc.mux_grid VALUES ('159/113', '0106000020E61000000100000001030000000100000005000000F93E7638954248C0C8F4386F4A3726C0C9EA1A7E0FCB47C0E9F9EA60C77E26C0A12E0E1DD0E447C0834D6CCD224928C0D08269D7555C48C06248BADBA50128C0F93E7638954248C0C8F4386F4A3726C0', 271, 271, 1898, -11.6454000000000004, -48.1088999999999984, 'S 11 38 43', 'O 48 06 32', 159, 113);
INSERT INTO bdc.mux_grid VALUES ('159/114', '0106000020E61000000100000001030000000100000005000000B2E6EAC55A5C48C0FED99AE8A20128C0227836A8D9E447C04EA022181D4928C0629A16CAB7FE47C0A5F4F8CA65132AC0F108CBE7387648C0552E719BEBCB29C0B2E6EAC55A5C48C0FED99AE8A20128C0', 272, 272, 1899, -12.5404999999999998, -48.3108000000000004, 'S 12 32 25', 'O 48 18 38', 159, 114);
INSERT INTO bdc.mux_grid VALUES ('159/115', '0106000020E610000001000000010300000001000000050000008019C2433E7648C09D94D966E8CB29C0F3CADA26C2FE47C0AD8350985F132AC021207D4EC01848C0E8F2952094DD2BC0AE6E646B3C9048C0D7031FEF1C962BC08019C2433E7648C09D94D966E8CB29C0', 273, 273, 1900, -13.4354999999999993, -48.5135999999999967, 'S 13 26 07', 'O 48 30 48', 159, 115);
INSERT INTO bdc.mux_grid VALUES ('159/116', '0106000020E610000001000000010300000001000000050000005DC68A37429048C0AAFF6D7719962BC02CD52482CB1848C08E52666D8DDD2BC0FD452F43EC3248C0F8471B58ACA72DC02E3795F862AA48C015F5226238602DC05DC68A37429048C0AAFF6D7719962BC0', 274, 274, 1901, -14.3302999999999994, -48.7173999999999978, 'S 14 19 49', 'O 48 43 02', 159, 116);
INSERT INTO bdc.mux_grid VALUES ('159/117', '0106000020E61000000100000001030000000100000005000000342CE53769AA48C0788F90A534602DC0596E7E53F83248C057B1F120A5A72DC08978F1533E4D48C01D63B5F8AC712FC064365838AFC448C03E41547D3C2A2FC0342CE53769AA48C0788F90A534602DC0', 275, 275, 1903, -15.2249999999999996, -48.9224000000000032, 'S 15 13 29', 'O 48 55 20', 159, 117);
INSERT INTO bdc.mux_grid VALUES ('159/118', '0106000020E61000000100000001030000000100000005000000F43610EEB5C448C0EEC8EF79382A2FC0FECA2E474B4D48C080D6D039A5712FC034720441B96748C0E8534943CA9D30C02ADEE5E723DF48C021CD58E3137A30C0F43610EEB5C448C0EEC8EF79382A2FC0', 276, 276, 1905, -16.1193999999999988, -49.1285999999999987, 'S 16 07 09', 'O 49 07 42', 159, 118);
INSERT INTO bdc.mux_grid VALUES ('159/119', '0106000020E6100000010000000103000000010000000500000005278C172BDF48C08DB52FBD117A30C0F18F001EC76748C01CD4EF1DC69D30C0A968E2E05F8248C0C66044C1B08231C0BEFF6DDAC3F948C038428460FC5E31C005278C172BDF48C08DB52FBD117A30C0', 277, 277, 1906, -17.0137, -49.3359999999999985, 'S 17 00 49', 'O 49 20 09', 159, 119);
INSERT INTO bdc.mux_grid VALUES ('159/120', '0106000020E610000001000000010300000001000000050000008FB1D487CBF948C015CBBF14FA5E31C02EB6FFAE6E8248C09251CE53AC8231C0E8621622359D48C0487FD834896732C0485EEBFA911449C0CCF8C9F5D64332C08FB1D487CBF948C015CBBF14FA5E31C0', 278, 278, 1908, -17.9076999999999984, -49.5448999999999984, 'S 17 54 27', 'O 49 32 41', 159, 120);
INSERT INTO bdc.mux_grid VALUES ('159/121', '0106000020E610000001000000010300000001000000050000007AFD342A9A1449C070932D83D44332C0E0AA51E9449D48C02E5EE27C846732C02D58300D3CB848C03B6C7DDA524C33C0C7AA134E912F49C07FA1C8E0A22833C07AFD342A9A1449C070932D83D44332C0', 279, 279, 1909, -18.8016000000000005, -49.7550999999999988, 'S 18 48 05', 'O 49 45 18', 159, 121);
INSERT INTO bdc.mux_grid VALUES ('159/122', '0106000020E610000001000000010300000001000000050000002111B8039A2F49C0433AFE45A02833C0CC452AD64CB848C087B472D54D4C33C041EBD8C677D348C029DF59EC0C3134C096B666F4C44A49C0E564E55C5F0D34C02111B8039A2F49C0433AFE45A02833C0', 280, 280, 1910, -19.6951000000000001, -49.9669999999999987, 'S 19 41 42', 'O 49 58 01', 159, 122);
INSERT INTO bdc.mux_grid VALUES ('159/123', '0106000020E610000001000000010300000001000000050000006C7F3835CE4A49C0F1C37B985C0D34C0F272E09A89D348C009ED7197073134C065E00792EBEE48C0118E01A2B61535C0DEEC5F2C306649C0FA640BA30BF234C06C7F3835CE4A49C0F1C37B985C0D34C0', 281, 281, 1911, -20.5884999999999998, -50.1805000000000021, 'S 20 35 18', 'O 50 10 49', 159, 123);
INSERT INTO bdc.mux_grid VALUES ('159/124', '0106000020E61000000100000001030000000100000005000000056C92FD396649C0AE6574B308F234C0A3A9257BFEEE48C0D5343CFAB01535C0C6B160D29A0A49C043CB2C304FFA35C02774CD54D68149C01CFC64E9A6D635C0056C92FD396649C0AE6574B308F234C0', 282, 282, 1912, -21.4816000000000003, -50.3956999999999979, 'S 21 28 53', 'O 50 23 44', 159, 124);
INSERT INTO bdc.mux_grid VALUES ('159/125', '0106000020E61000000100000001030000000100000005000000913EFBBBE08149C0D298F3CCA3D635C0C49D63DBAE0A49C054964E3249FA35C046FEB80E892649C03C1869C8D5DE36C0139F50EFBA9D49C0BB1A0E6330BB36C0913EFBBBE08149C0D298F3CCA3D635C0', 283, 283, 1913, -22.3744000000000014, -50.6129000000000033, 'S 22 22 27', 'O 50 36 46', 159, 125);
INSERT INTO bdc.mux_grid VALUES ('159/126', '0106000020E61000000100000001030000000100000005000000ABB882F2C59D49C02347F4172DBB36C0BDE243439E2649C00230F770CFDE36C057E8CCF3B94249C02F11C29849C337C045BE0BA3E1B949C05128BF3FA79F37C0ABB882F2C59D49C02347F4172DBB36C0', 284, 284, 1915, -23.2669999999999995, -50.8320000000000007, 'S 23 16 01', 'O 50 49 55', 159, 126);
INSERT INTO bdc.mux_grid VALUES ('159/127', '0106000020E610000001000000010300000001000000050000001177C148EDB949C074770BC4A39F37C02E9F6560D04249C006BAFDE342C337C0C2E82557315F49C0EAF961CBA9A738C0A5C0813F4ED649C058B76FAB0A8438C01177C148EDB949C074770BC4A39F37C0', 285, 285, 1916, -24.1593000000000018, -51.0531000000000006, 'S 24 09 33', 'O 51 03 11', 159, 127);
INSERT INTO bdc.mux_grid VALUES ('159/128', '0106000020E61000000100000001030000000100000005000000E45CB98E5AD649C0D1C40AFD068438C0B9D74509495F49C096A243B5A2A738C0EF0C393AF37B49C06E132986F58B39C01A92ACBF04F349C0AA35F0CD596839C0E45CB98E5AD649C0D1C40AFD068438C0', 286, 286, 1918, -25.0512000000000015, -51.2764999999999986, 'S 25 03 04', 'O 51 16 35', 159, 128);
INSERT INTO bdc.mux_grid VALUES ('159/129', '0106000020E610000001000000010300000001000000050000004AC6ECBF11F349C086CF99EA556839C0B0465F400C7C49C032E95A0AEE8B39C0FD1AC2CD039949C093EF3AEA2B703AC0979A4F4D09104AC0E8D579CA934C3AC04AC6ECBF11F349C086CF99EA556839C0', 287, 287, 1919, -25.9429000000000016, -51.502200000000002, 'S 25 56 34', 'O 51 30 07', 159, 129);
INSERT INTO bdc.mux_grid VALUES ('159/130', '0106000020E6100000010000000103000000010000000500000094F9B10617104AC02ADEC5AF8F4C3AC06D4B87371E9949C0E4E8120424703AC09CB3617567B649C0C3BE80134C543BC0C2618C44602D4AC007B433BFB7303BC094F9B10617104AC02ADEC5AF8F4C3AC0', 288, 288, 1920, -26.8341999999999992, -51.730400000000003, 'S 26 50 03', 'O 51 43 49', 159, 130);
INSERT INTO bdc.mux_grid VALUES ('159/131', '0106000020E61000000100000001030000000100000005000000F1D2C8BF6E2D4AC01CB3866AB3303BC0EBFE8D5383B649C0D310FABD43543BC0362385CB22D449C0CA891F1855383CC03CF7BF370E4B4AC0132CACC4C4143CC0F1D2C8BF6E2D4AC01CB3866AB3303BC0', 289, 289, 1921, -27.7251000000000012, -51.9611000000000018, 'S 27 43 30', 'O 51 57 40', 159, 131);
INSERT INTO bdc.mux_grid VALUES ('159/132', '0106000020E610000001000000010300000001000000050000004B55397E1D4B4AC0B18A3733C0143CC09A36283040D449C02376D34D4C383CC03C639FA53AF249C08A2BE107461C3DC0EE81B0F317694AC0174045EDB9F83CC04B55397E1D4B4AC0B18A3733C0143CC0', 290, 290, 1922, -28.6157000000000004, -52.1946000000000012, 'S 28 36 56', 'O 52 11 40', 159, 132);
INSERT INTO bdc.mux_grid VALUES ('159/133', '0106000020E61000000100000001030000000100000005000000817C820F28694AC07E20031CB5F83CC0C9EA2AA459F249C04E16FFC23C1C3DC0AD8EBB18B4104AC0ABBA8EEB1D003EC06520138482874AC0DBC4924496DC3DC0817C820F28694AC07E20031CB5F83CC0', 291, 291, 1923, -29.5060000000000002, -52.4309999999999974, 'S 29 30 21', 'O 52 25 51', 159, 133);
INSERT INTO bdc.mux_grid VALUES ('159/134', '0106000020E61000000100000001030000000100000005000000898A218093874AC0F56E413091DC3DC0F25A20C6D4104AC01873D32514003EC0C30D727E942F4AC030ED3AC4DBE33EC05A3D733853A64AC00FE9A8CE58C03EC0898A218093874AC0F56E413091DC3DC0', 292, 292, 1924, -30.3958000000000013, -52.670499999999997, 'S 30 23 44', 'O 52 40 13', 159, 134);
INSERT INTO bdc.mux_grid VALUES ('159/135', '0106000020E6100000010000000103000000010000000500000053EE7A2065A64AC04ABEC57353C03EC0FD3540F1B62F4AC08F11E776D1E33EC0FBC44A7AE14E4AC0BECA7A8A7EC73FC0507D85A98FC54AC07977598700A43FC053EE7A2065A64AC04ABEC57353C03EC0', 293, 293, 1927, -31.2852999999999994, -52.9131, 'S 31 17 06', 'O 52 54 47', 159, 135);
INSERT INTO bdc.mux_grid VALUES ('159/136', '0106000020E6100000010000000103000000010000000500000065F32E8AA2C54AC007601BE2FAA33FC06615D5CA054F4AC0C52F48AE73C73FC06BC497FFA06E4AC00C78C596825540C069A2F1BE3DE54AC02C10AF30C64340C065F32E8AA2C54AC007601BE2FAA33FC0', 294, 294, 1928, -32.1743000000000023, -53.1591999999999985, 'S 32 10 27', 'O 53 09 32', 159, 136);
INSERT INTO bdc.mux_grid VALUES ('159/137', '0106000020E61000000100000001030000000100000005000000449DE5A551E54AC0EEB0D736C34340C05DE41A48C76E4AC0EC7550DD7C5540C0765DD557D98E4AC03AA12F4937C740C05E16A0B563054BC03ADCB6A27DB540C0449DE5A551E54AC0EEB0D736C34340C0', 295, 295, 1929, -33.0628999999999991, -53.4087999999999994, 'S 33 03 46', 'O 53 24 31', 159, 137);
INSERT INTO bdc.mux_grid VALUES ('160/101', '0106000020E6100000010000000103000000010000000500000052AFDF85A98E47C03676E2565CECD6BF0BD4036B081747C0DDCE818906DEDFBF356C27021A3047C0D3FDAB51EE4DF6BF7D47031DBBA747C0AA2704C58311F4BF52AFDF85A98E47C03676E2565CECD6BF', 296, 296, 1986, -0.896100000000000008, -46.7002000000000024, 'S 00 53 45', 'O 46 42 00', 160, 101);
INSERT INTO bdc.mux_grid VALUES ('160/102', '0106000020E61000000100000001030000000100000005000000B293856FBBA747C0F8BC373A8211F4BFC5B727BE1A3047C05B261ACEEA4DF6BF6DDCDEF62E4947C0195B579B245202C05AB83CA8CFC047C068266651F03301C0B293856FBBA747C0F8BC373A8211F4BF', 297, 297, 1987, -1.79220000000000002, -46.896099999999997, 'S 01 47 31', 'O 46 53 45', 160, 102);
INSERT INTO bdc.mux_grid VALUES ('160/103', '0106000020E6100000010000000103000000010000000500000027D1F357D0C047C0D9FB01ADEE3301C06687AD64304947C0DBA42930215202C071AC925B496247C0E4F73AA7437D09C032F6D84EE9D947C0E24E1324115F08C027D1F357D0C047C0D9FB01ADEE3301C0', 298, 298, 1988, -2.68829999999999991, -47.0921000000000021, 'S 02 41 17', 'O 47 05 31', 160, 103);
INSERT INTO bdc.mux_grid VALUES ('160/104', '0106000020E61000000100000001030000000100000005000000D65E185CEAD947C02762E99F0E5F08C079E9DD7B4B6247C04CB407913E7D09C0051DE04F6B7B47C0CAF04658275410C061921A300AF347C06F8F6FBF1E8A0FC0D65E185CEAD947C02762E99F0E5F08C0', 299, 299, 1990, -3.58429999999999982, -47.2882999999999996, 'S 03 35 03', 'O 47 17 18', 160, 104);
INSERT INTO bdc.mux_grid VALUES ('160/105', '0106000020E61000000100000001030000000100000005000000157F629B0BF347C089274D5A1B8A0FC0C496AB236E7B47C068E973F6235410C0BE1F1AF7969447C038BDD50CA0E913C00F08D16E340C48C0946788C3895A13C0157F629B0BF347C089274D5A1B8A0FC0', 300, 300, 1991, -4.48029999999999973, -47.4847999999999999, 'S 04 28 49', 'O 47 29 05', 160, 105);
INSERT INTO bdc.mux_grid VALUES ('160/106', '0106000020E61000000100000001030000000100000005000000BBE1CE38360C48C0F485AB9F875A13C0AD01C07F9A9447C01337ABD29BE913C01F7B5979CEAD47C0B6E66221097F17C02C5B68326A2548C0943563EEF4EF16C0BBE1CE38360C48C0F485AB9F875A13C0', 301, 301, 1992, -5.37619999999999987, -47.6816000000000031, 'S 05 22 34', 'O 47 40 53', 160, 106);
INSERT INTO bdc.mux_grid VALUES ('160/107', '0106000020E610000001000000010300000001000000050000002B72F75B6C2548C0C44C3458F2EF16C02AD48BB8D2AD47C01FA6D90C047F17C0A2E0910414C747C06C5CB3C45F141BC0A47EFDA7AD3E48C011030E104E851AC02B72F75B6C2548C0C44C3458F2EF16C0', 302, 302, 1993, -6.27210000000000001, -47.8787999999999982, 'S 06 16 19', 'O 47 52 43', 160, 107);
INSERT INTO bdc.mux_grid VALUES ('160/108', '0106000020E61000000100000001030000000100000005000000E2ED2732B03E48C07AC04E064B851AC0B4605CFC18C747C043EE58D359141BC0311AADCD69E047C01628F423A1A91EC060A77803015848C04DFAE956921A1EC0E2ED2732B03E48C07AC04E064B851AC0', 303, 303, 1995, -7.16790000000000038, -48.0765000000000029, 'S 07 10 04', 'O 48 04 35', 160, 108);
INSERT INTO bdc.mux_grid VALUES ('160/109', '0106000020E61000000100000001030000000100000005000000DB6878EF035848C071C722D88E1A1EC0772F77806FE047C0495AE8529AA91EC0B881AD11D2F947C021B23835651F21C01CBBAE80667148C0B4E8D577DFD720C0DB6878EF035848C071C722D88E1A1EC0', 304, 304, 1997, -8.06359999999999921, -48.2747000000000028, 'S 08 03 49', 'O 48 16 28', 160, 109);
INSERT INTO bdc.mux_grid VALUES ('160/110', '0106000020E6100000010000000103000000010000000500000051F0EECF697148C08925157DDDD720C06CD73C82D8F947C0D2A4315B611F21C037FFD8164F1348C0498DA360ECE922C01D188B64E08A48C0FF0D878268A222C051F0EECF697148C08925157DDDD720C0', 305, 305, 1998, -8.95919999999999916, -48.473399999999998, 'S 08 57 33', 'O 48 28 24', 160, 110);
INSERT INTO bdc.mux_grid VALUES ('160/111', '0106000020E610000001000000010300000001000000050000005688A918E48A48C070A4714B66A222C0D4635448561348C080C93813E8E922C01FDCED2DE32C48C0DE8D85A764B424C0A10043FE70A448C0CD68BEDFE26C24C05688A918E48A48C070A4714B66A222C0', 306, 306, 1999, -9.85479999999999912, -48.6728999999999985, 'S 09 51 17', 'O 48 40 22', 160, 111);
INSERT INTO bdc.mux_grid VALUES ('160/112', '0106000020E6100000010000000103000000010000000500000074CF111975A448C0E48A3D6BE06C24C0BB93E023EB2C48C0826D98E45FB424C012CB62B3904648C03F73B79BCC7E26C0CB0694A81ABE48C0A0905C224D3726C074CF111975A448C0E48A3D6BE06C24C0', 307, 307, 2001, -10.7501999999999995, -48.8731000000000009, 'S 10 45 00', 'O 48 52 23', 160, 112);
INSERT INTO bdc.mux_grid VALUES ('160/113', '0106000020E610000001000000010300000001000000050000009CA61B2C1FBE48C0F7F4386F4A3726C06D52C071994648C018FAEA60C77E26C03F96B3105A6048C0304D6CCD224928C06CEA0ECBDFD748C00F48BADBA50128C09CA61B2C1FBE48C0F7F4386F4A3726C0', 308, 308, 2002, -11.6454000000000004, -49.0739999999999981, 'S 11 38 43', 'O 49 04 26', 160, 113);
INSERT INTO bdc.mux_grid VALUES ('160/114', '0106000020E61000000100000001030000000100000005000000604E90B9E4D748C0A4D99AE8A20128C0ADDFDB9B636048C009A022181D4928C0EC01BCBD417A48C05DF4F8CA65132AC09F7070DBC2F148C0F92D719BEBCB29C0604E90B9E4D748C0A4D99AE8A20128C0', 309, 309, 2003, -12.5404999999999998, -49.2759, 'S 12 32 25', 'O 49 16 33', 160, 114);
INSERT INTO bdc.mux_grid VALUES ('160/115', '0106000020E6100000010000000103000000010000000500000023816737C8F148C04A94D966E8CB29C09532801A4C7A48C05A8350985F132AC0CA8722424A9448C013F3952094DD2BC058D6095FC60B49C002041FEF1C962BC023816737C8F148C04A94D966E8CB29C0', 310, 310, 2004, -13.4354999999999993, -49.4787000000000035, 'S 13 26 07', 'O 49 28 43', 160, 115);
INSERT INTO bdc.mux_grid VALUES ('160/116', '0106000020E61000000100000001030000000100000005000000012E302BCC0B49C0DAFF6D7719962BC0F33CCA75559448C0AA52666D8DDD2BC0C2ADD43676AE48C013481B58ACA72DC0D19E3AECEC2549C043F5226238602DC0012E302BCC0B49C0DAFF6D7719962BC0', 311, 311, 2006, -14.3302999999999994, -49.6826000000000008, 'S 14 19 49', 'O 49 40 57', 160, 116);
INSERT INTO bdc.mux_grid VALUES ('160/117', '0106000020E61000000100000001030000000100000005000000CF938A2BF32549C0AC8F90A534602DC017D6234782AE48C077B1F120A5A72DC03FE09647C8C848C0BE62B5F8AC712FC0F89DFD2B394049C0F340547D3C2A2FC0CF938A2BF32549C0AC8F90A534602DC0', 312, 312, 2007, -15.2249999999999996, -49.8875000000000028, 'S 15 13 29', 'O 49 53 15', 160, 117);
INSERT INTO bdc.mux_grid VALUES ('160/118', '0106000020E61000000100000001030000000100000005000000AF9EB5E13F4049C08CC8EF79382A2FC09732D43AD5C848C031D6D039A5712FC0CED9A93443E348C0C1534943CA9D30C0E6458BDBAD5A49C0F0CC58E3137A30C0AF9EB5E13F4049C08CC8EF79382A2FC0', 313, 313, 2009, -16.1193999999999988, -50.0936999999999983, 'S 16 07 09', 'O 50 05 37', 160, 118);
INSERT INTO bdc.mux_grid VALUES ('160/119', '0106000020E61000000100000001030000000100000005000000908E310BB55A49C06AB52FBD117A30C07BF7A51151E348C0F8D3EF1DC69D30C033D087D4E9FD48C0A46044C1B08231C0486713CE4D7549C016428460FC5E31C0908E310BB55A49C06AB52FBD117A30C0', 314, 314, 2011, -17.0137, -50.3012000000000015, 'S 17 00 49', 'O 50 18 04', 160, 119);
INSERT INTO bdc.mux_grid VALUES ('160/120', '0106000020E610000001000000010300000001000000050000000D197A7B557549C0F6CABF14FA5E31C0D01DA5A2F8FD48C06851CE53AC8231C08ACABB15BF1849C01F7FD834896732C0C6C590EE1B9049C0ACF8C9F5D64332C00D197A7B557549C0F6CABF14FA5E31C0', 315, 315, 2012, -17.9076999999999984, -50.509999999999998, 'S 17 54 27', 'O 50 30 36', 160, 120);
INSERT INTO bdc.mux_grid VALUES ('160/121', '0106000020E610000001000000010300000001000000050000002A65DA1D249049C043932D83D44332C06E12F7DCCE1849C00B5EE27C846732C0C3BFD500C63349C0576C7DDA524C33C08012B9411BAB49C091A1C8E0A22833C02A65DA1D249049C043932D83D44332C0', 316, 316, 2013, -18.8016000000000005, -50.7203000000000017, 'S 18 48 05', 'O 50 43 13', 160, 121);
INSERT INTO bdc.mux_grid VALUES ('160/122', '0106000020E61000000100000001030000000100000005000000A5785DF723AB49C0653AFE45A02833C095ADCFC9D63349C094B472D54D4C33C0FA527EBA014F49C0B6DE59EC0C3134C00A1E0CE84EC649C08764E55C5F0D34C0A5785DF723AB49C0653AFE45A02833C0', 317, 317, 2014, -19.6951000000000001, -50.9320999999999984, 'S 19 41 42', 'O 50 55 55', 160, 122);
INSERT INTO bdc.mux_grid VALUES ('160/123', '0106000020E61000000100000001030000000100000005000000EBE6DD2858C649C090C37B985C0D34C072DA858E134F49C0A8EC7197073134C00348AD85756A49C0B08E01A2B61535C07C540520BAE149C099650BA30BF234C0EBE6DD2858C649C090C37B985C0D34C0', 318, 318, 2015, -20.5884999999999998, -51.1456000000000017, 'S 20 35 18', 'O 51 08 44', 160, 123);
INSERT INTO bdc.mux_grid VALUES ('160/124', '0106000020E61000000100000001030000000100000005000000E9D337F1C3E149C0376674B308F234C04311CB6E886A49C072353CFAB01535C0571906C6248649C061CB2C304FFA35C0FEDB724860FD49C027FC64E9A6D635C0E9D337F1C3E149C0376674B308F234C0', 319, 319, 2017, -21.4816000000000003, -51.3609000000000009, 'S 21 28 53', 'O 51 21 39', 160, 124);
INSERT INTO bdc.mux_grid VALUES ('160/125', '0106000020E6100000010000000103000000010000000500000093A6A0AF6AFD49C0CE98F3CCA3D635C03B0509CF388649C07A964E3249FA35C0BD655E0213A249C0631869C8D5DE36C01507F6E244194AC0B71A0E6330BB36C093A6A0AF6AFD49C0CE98F3CCA3D635C0', 320, 320, 2018, -22.3744000000000014, -51.578000000000003, 'S 22 22 27', 'O 51 34 40', 160, 125);
INSERT INTO bdc.mux_grid VALUES ('160/126', '0106000020E61000000100000001030000000100000005000000382028E64F194AC04147F4172DBB36C0924AE93628A249C00B30F770CFDE36C03A5072E743BE49C0BB11C29849C337C0E225B1966B354AC0EF28BF3FA79F37C0382028E64F194AC04147F4172DBB36C0', 321, 321, 2020, -23.2669999999999995, -51.7971000000000004, 'S 23 16 01', 'O 51 47 49', 160, 126);
INSERT INTO bdc.mux_grid VALUES ('160/127', '0106000020E61000000100000001030000000100000005000000B5DE663C77354AC012780BC4A39F37C018070B545ABE49C08FBAFDE342C337C08B50CB4ABBDA49C072F961CBA9A738C029282733D8514AC0F6B66FAB0A8438C0B5DE663C77354AC012780BC4A39F37C0', 322, 322, 2022, -24.1593000000000018, -52.0183000000000035, 'S 24 09 33', 'O 52 01 05', 160, 127);
INSERT INTO bdc.mux_grid VALUES ('160/128', '0106000020E6100000010000000103000000010000000500000099C45E82E4514AC060C40AFD068438C0293FEBFCD2DA49C03AA243B5A2A738C05E74DE2D7DF749C012132986F58B39C0CEF951B38E6E4AC03935F0CD596839C099C45E82E4514AC060C40AFD068438C0', 323, 323, 2023, -25.0512000000000015, -52.2415999999999983, 'S 25 03 04', 'O 52 14 29', 160, 128);
INSERT INTO bdc.mux_grid VALUES ('160/129', '0106000020E61000000100000001030000000100000005000000482E92B39B6E4AC0FFCE99EA556839C022AE043496F749C0D4E85A0AEE8B39C0808267C18D144AC0B6EF3AEA2B703AC0A702F540938B4AC0E1D579CA934C3AC0482E92B39B6E4AC0FFCE99EA556839C0', 324, 324, 2024, -25.9429000000000016, -52.4673999999999978, 'S 25 56 34', 'O 52 28 02', 160, 129);
INSERT INTO bdc.mux_grid VALUES ('160/130', '0106000020E61000000100000001030000000100000005000000296157FAA08B4AC047DEC5AF8F4C3AC002B32C2BA8144AC002E9120424703AC01F1B0769F1314AC060BE80134C543BC046C93138EAA84AC0A4B333BFB7303BC0296157FAA08B4AC047DEC5AF8F4C3AC0', 325, 325, 2025, -26.8341999999999992, -52.6955000000000027, 'S 26 50 03', 'O 52 41 43', 160, 130);
INSERT INTO bdc.mux_grid VALUES ('160/131', '0106000020E61000000100000001030000000100000005000000A33A6EB3F8A84AC0ABB2866AB3303BC09E6633470D324AC06210FABD43543BC0E98A2ABFAC4F4AC058891F1855383CC0EE5E652B98C64AC0A12BACC4C4143CC0A33A6EB3F8A84AC0ABB2866AB3303BC0', 326, 326, 2027, -27.7251000000000012, -52.9262999999999977, 'S 27 43 30', 'O 52 55 34', 160, 131);
INSERT INTO bdc.mux_grid VALUES ('160/132', '0106000020E6100000010000000103000000010000000500000002BDDE71A7C64AC03F8A3733C0143CC0549ECD23CA4F4AC0B075D34D4C383CC0F5CA4499C46D4AC0172BE107461C3DC0A6E955E7A1E44AC0A53F45EDB9F83CC002BDDE71A7C64AC03F8A3733C0143CC0', 327, 327, 2028, -28.6157000000000004, -53.1597999999999971, 'S 28 36 56', 'O 53 09 35', 160, 132);
INSERT INTO bdc.mux_grid VALUES ('160/133', '0106000020E6100000010000000103000000010000000500000042E42703B2E44AC00A20031CB5F83CC04852D097E36D4AC0EF15FFC23C1C3DC03AF6600C3E8C4AC0C9BA8EEB1D003EC03988B8770C034BC0E4C4924496DC3DC042E42703B2E44AC00A20031CB5F83CC0', 328, 328, 2029, -29.5060000000000002, -53.3962000000000003, 'S 29 30 21', 'O 53 23 46', 160, 133);
INSERT INTO bdc.mux_grid VALUES ('160/134', '0106000020E610000001000000010300000001000000050000001DF2C6731D034BC0116F413091DC3DC0CCC2C5B95E8C4AC02173D32514003EC08E7517721EAB4AC0BAEC3AC4DBE33EC0DEA4182CDD214BC0ADE8A8CE58C03EC01DF2C6731D034BC0116F413091DC3DC0', 329, 329, 2030, -30.3958000000000013, -53.6355999999999966, 'S 30 23 44', 'O 53 38 08', 160, 134);
INSERT INTO bdc.mux_grid VALUES ('160/135', '0106000020E61000000100000001030000000100000005000000CD552014EF214BC0EBBDC57353C03EC0BB9DE5E440AB4AC01911E776D1E33EC0B82CF06D6BCA4AC04ACA7A8A7EC73FC0CBE42A9D19414BC01C77598700A43FC0CD552014EF214BC0EBBDC57353C03EC0', 330, 330, 2032, -31.2852999999999994, -53.878300000000003, 'S 31 17 06', 'O 53 52 41', 160, 135);
INSERT INTO bdc.mux_grid VALUES ('160/136', '0106000020E61000000100000001030000000100000005000000E45AD47D2C414BC0A85F1BE2FAA33FC0E57C7ABE8FCA4AC0662F48AE73C73FC00D2C3DF32AEA4AC05A78C596825540C00C0A97B2C7604BC07A10AF30C64340C0E45AD47D2C414BC0A85F1BE2FAA33FC0', 331, 331, 2033, -32.1743000000000023, -54.1242999999999981, 'S 32 10 27', 'O 54 07 27', 160, 136);
INSERT INTO bdc.mux_grid VALUES ('160/137', '0106000020E61000000100000001030000000100000005000000BC048B99DB604BC040B1D736C34340C0194CC03B51EA4AC0367650DD7C5540C021C57A4B630A4BC044A12F4937C740C0C47D45A9ED804BC050DCB6A27DB540C0BC048B99DB604BC040B1D736C34340C0', 332, 332, 2035, -33.0628999999999991, -54.373899999999999, 'S 33 03 46', 'O 54 22 26', 160, 137);
INSERT INTO bdc.mux_grid VALUES ('160/138', '0106000020E610000001000000010300000001000000050000000EC743A502814BC0EE92727F7AB540C0287C48A88B0A4BC0D2DD224031C740C0EA6B431D1B2B4BC0046A4DC9DC3841C0D0B63E1A92A14BC0201F9D08262741C00EC743A502814BC0EE92727F7AB540C0', 333, 333, 2036, -33.9510000000000005, -54.6272999999999982, 'S 33 57 03', 'O 54 37 38', 160, 138);
INSERT INTO bdc.mux_grid VALUES ('161/101', '0106000020E61000000100000001030000000100000005000000F6168579330A48C0F975E2565CECD6BFB03BA95E929247C09DCE818906DEDFBFDAD3CCF5A3AB47C0F4FDAB51EE4DF6BF21AFA810452348C0C62704C58311F4BFF6168579330A48C0F975E2565CECD6BF', 334, 334, 2098, -0.896100000000000008, -47.665300000000002, 'S 00 53 45', 'O 47 39 55', 161, 101);
INSERT INTO bdc.mux_grid VALUES ('161/102', '0106000020E6100000010000000103000000010000000500000057FB2A63452348C015BD373A8211F4BF671FCDB1A4AB47C08D261ACEEA4DF6BF0F4484EAB8C447C01B5B579B245202C0FF1FE29B593C48C05F266651F03301C057FB2A63452348C015BD373A8211F4BF', 335, 335, 2099, -1.79220000000000002, -47.8611999999999966, 'S 01 47 31', 'O 47 51 40', 161, 102);
INSERT INTO bdc.mux_grid VALUES ('161/103', '0106000020E61000000100000001030000000100000005000000CE38994B5A3C48C0C8FB01ADEE3301C00AEF5258BAC447C0D4A42930215202C01514384FD3DD47C0A8F73AA7437D09C0DA5D7E42735548C09E4E1324115F08C0CE38994B5A3C48C0C8FB01ADEE3301C0', 336, 336, 2101, -2.68829999999999991, -48.0572999999999979, 'S 02 41 17', 'O 48 03 26', 161, 103);
INSERT INTO bdc.mux_grid VALUES ('161/104', '0106000020E6100000010000000103000000010000000500000076C6BD4F745548C0F361E99F0E5F08C01A51836FD5DD47C017B407913E7D09C0A3848543F5F647C074F04658275410C0FFF9BF23946E48C0C48E6FBF1E8A0FC076C6BD4F745548C0F361E99F0E5F08C0', 337, 337, 2102, -3.58429999999999982, -48.2535000000000025, 'S 03 35 03', 'O 48 15 12', 161, 104);
INSERT INTO bdc.mux_grid VALUES ('161/105', '0106000020E61000000100000001030000000100000005000000B7E6078F956E48C0D2264D5A1B8A0FC05EFE5017F8F647C018E973F6235410C05B87BFEA201048C03CBDD50CA0E913C0B46F7662BE8748C08D6788C3895A13C0B7E6078F956E48C0D2264D5A1B8A0FC0', 338, 338, 2103, -4.48029999999999973, -48.4500000000000028, 'S 04 28 49', 'O 48 26 59', 161, 105);
INSERT INTO bdc.mux_grid VALUES ('161/106', '0106000020E610000001000000010300000001000000050000005949742CC08748C0F585AB9F875A13C05D696573241048C00037ABD29BE913C0CFE2FE6C582948C0A7E66221097F17C0CAC20D26F4A048C09C3563EEF4EF16C05949742CC08748C0F585AB9F875A13C0', 339, 339, 2104, -5.37619999999999987, -48.6467999999999989, 'S 05 22 34', 'O 48 38 48', 161, 106);
INSERT INTO bdc.mux_grid VALUES ('161/107', '0106000020E61000000100000001030000000100000005000000D5D99C4FF6A048C0C04C3458F2EF16C0D33B31AC5C2948C01CA6D90C047F17C04D4837F89D4248C0AA5CB3C45F141BC04FE6A29B37BA48C050030E104E851AC0D5D99C4FF6A048C0C04C3458F2EF16C0', 340, 340, 2106, -6.27210000000000001, -48.8440000000000012, 'S 06 16 19', 'O 48 50 38', 161, 107);
INSERT INTO bdc.mux_grid VALUES ('161/108', '0106000020E610000001000000010300000001000000050000007355CD253ABA48C0D9C04E064B851AC068C801F0A24248C07AEE58D359141BC0E38152C1F35B48C01328F423A1A91EC0EE0E1EF78AD348C071FAE956921A1EC07355CD253ABA48C0D9C04E064B851AC0', 341, 341, 2107, -7.16790000000000038, -49.0416000000000025, 'S 07 10 04', 'O 49 02 29', 161, 108);
INSERT INTO bdc.mux_grid VALUES ('161/109', '0106000020E610000001000000010300000001000000050000007FD01DE38DD348C07CC722D88E1A1EC01B971C74F95B48C0545AE8529AA91EC05EE952055C7548C03BB23835651F21C0C3225474F0EC48C0CFE8D577DFD720C07FD01DE38DD348C07CC722D88E1A1EC0', 342, 342, 2109, -8.06359999999999921, -49.2398000000000025, 'S 08 03 49', 'O 49 14 23', 161, 109);
INSERT INTO bdc.mux_grid VALUES ('161/110', '0106000020E61000000100000001030000000100000005000000F75794C3F3EC48C0A225157DDDD720C0FE3EE275627548C0F4A4315B611F21C0C8667E0AD98E48C04C8DA360ECE922C0C07F30586A0649C0FB0D878268A222C0F75794C3F3EC48C0A225157DDDD720C0', 343, 343, 2110, -8.95919999999999916, -49.438600000000001, 'S 08 57 33', 'O 49 26 18', 161, 110);
INSERT INTO bdc.mux_grid VALUES ('161/111', '0106000020E61000000100000001030000000100000005000000F4EF4E0C6E0649C06CA4714B66A222C085CBF93BE08E48C072C93813E8E922C0CD4393216DA848C0B38D85A764B424C03E68E8F1FA1F49C0AD68BEDFE26C24C0F4EF4E0C6E0649C06CA4714B66A222C0', 344, 344, 2112, -9.85479999999999912, -49.6379999999999981, 'S 09 51 17', 'O 49 38 16', 161, 111);
INSERT INTO bdc.mux_grid VALUES ('161/112', '0106000020E61000000100000001030000000100000005000000F336B70CFF1F49C0D58A3D6BE06C24C06DFB851775A848C0536D98E45FB424C0C73208A71AC248C03273B79BCC7E26C04D6E399CA43949C0B4905C224D3726C0F336B70CFF1F49C0D58A3D6BE06C24C0', 345, 345, 2113, -10.7501999999999995, -49.8382000000000005, 'S 10 45 00', 'O 49 50 17', 161, 112);
INSERT INTO bdc.mux_grid VALUES ('161/113', '0106000020E610000001000000010300000001000000050000003D0EC11FA93949C0F7F4386F4A3726C00DBA656523C248C017FAEA60C77E26C0E4FD5804E4DB48C0944D6CCD224928C01452B4BE695349C07348BADBA50128C03D0EC11FA93949C0F7F4386F4A3726C0', 346, 346, 2114, -11.6454000000000004, -50.039200000000001, 'S 11 38 43', 'O 50 02 21', 161, 113);
INSERT INTO bdc.mux_grid VALUES ('161/114', '0106000020E61000000100000001030000000100000005000000F5B535AD6E5349C010DA9AE8A20128C06447818FEDDB48C061A022181D4928C0A26961B1CBF548C09AF4F8CA65132AC034D815CF4C6D49C04A2E719BEBCB29C0F5B535AD6E5349C010DA9AE8A20128C0', 347, 347, 2115, -12.5404999999999998, -50.2409999999999997, 'S 12 32 25', 'O 50 14 27', 161, 114);
INSERT INTO bdc.mux_grid VALUES ('161/115', '0106000020E61000000100000001030000000100000005000000CDE80C2B526D49C08E94D966E8CB29C03F9A250ED6F548C09E8350985F132AC073EFC735D40F49C037F3952094DD2BC0013EAF52508749C028041FEF1C962BC0CDE80C2B526D49C08E94D966E8CB29C0', 348, 348, 2117, -13.4354999999999993, -50.4438999999999993, 'S 13 26 07', 'O 50 26 37', 161, 115);
INSERT INTO bdc.mux_grid VALUES ('161/116', '0106000020E61000000100000001030000000100000005000000A395D51E568749C001006E7719962BC095A46F69DF0F49C0CF52666D8DDD2BC063157A2A002A49C01C481B58ACA72DC07106E0DF76A149C04EF5226238602DC0A395D51E568749C001006E7719962BC0', 349, 349, 2118, -14.3302999999999994, -50.6477000000000004, 'S 14 19 49', 'O 50 38 51', 161, 116);
INSERT INTO bdc.mux_grid VALUES ('161/117', '0106000020E6100000010000000103000000010000000500000068FB2F1F7DA149C0BC8F90A534602DC0B03DC93A0C2A49C086B1F120A5A72DC0DD473C3B524449C03163B5F8AC712FC09605A31FC3BB49C06541547D3C2A2FC068FB2F1F7DA149C0BC8F90A534602DC0', 350, 350, 2119, -15.2249999999999996, -50.8526999999999987, 'S 15 13 29', 'O 50 51 09', 161, 117);
INSERT INTO bdc.mux_grid VALUES ('161/118', '0106000020E6100000010000000103000000010000000500000032065BD5C9BB49C00FC9EF79382A2FC05E9A792E5F4449C089D6D039A5712FC08F414F28CD5E49C0BC534943CA9D30C063AD30CF37D649C0FECC58E3137A30C032065BD5C9BB49C00FC9EF79382A2FC0', 351, 351, 2121, -16.1193999999999988, -51.0589000000000013, 'S 16 07 09', 'O 51 03 31', 161, 118);
INSERT INTO bdc.mux_grid VALUES ('161/119', '0106000020E6100000010000000103000000010000000500000041F6D6FE3ED649C069B52FBD117A30C00B5F4B05DB5E49C002D4EF1DC69D30C0C8372DC8737949C0DD6044C1B08231C0FECEB8C1D7F049C044428460FC5E31C041F6D6FE3ED649C069B52FBD117A30C0', 352, 352, 2122, -17.0137, -51.2663000000000011, 'S 17 00 49', 'O 51 15 58', 161, 119);
INSERT INTO bdc.mux_grid VALUES ('161/120', '0106000020E61000000100000001030000000100000005000000B9801F6FDFF049C027CBBF14FA5E31C05A854A96827949C0A651CE53AC8231C009326109499449C00E7FD834896732C0692D36E2A50B4AC08EF8C9F5D64332C0B9801F6FDFF049C027CBBF14FA5E31C0', 353, 353, 2123, -17.9076999999999984, -51.4750999999999976, 'S 17 54 27', 'O 51 28 30', 161, 120);
INSERT INTO bdc.mux_grid VALUES ('161/121', '0106000020E61000000100000001030000000100000005000000DCCC7F11AE0B4AC020932D83D44332C0207A9CD0589449C0E95DE27C846732C073277BF44FAF49C0286C7DDA524C33C0307A5E35A5264AC060A1C8E0A22833C0DCCC7F11AE0B4AC020932D83D44332C0', 354, 354, 2124, -18.8016000000000005, -51.6854000000000013, 'S 18 48 05', 'O 51 41 07', 161, 121);
INSERT INTO bdc.mux_grid VALUES ('161/122', '0106000020E6100000010000000103000000010000000500000065E002EBAD264AC02E3AFE45A02833C0101575BD60AF49C073B472D54D4C33C07DBA23AE8BCA49C0C6DE59EC0C3134C0D085B1DBD8414AC08064E55C5F0D34C065E002EBAD264AC02E3AFE45A02833C0', 355, 355, 2125, -19.6951000000000001, -51.8973000000000013, 'S 19 41 42', 'O 51 53 50', 161, 122);
INSERT INTO bdc.mux_grid VALUES ('161/123', '0106000020E61000000100000001030000000100000005000000774E831CE2414AC09DC37B985C0D34C0FE412B829DCA49C0B5EC7197073134C08EAF5279FFE549C0AD8E01A2B61535C007BCAA13445D4AC095650BA30BF234C0774E831CE2414AC09DC37B985C0D34C0', 356, 356, 2127, -20.5884999999999998, -52.1107999999999976, 'S 20 35 18', 'O 52 06 38', 161, 123);
INSERT INTO bdc.mux_grid VALUES ('161/124', '0106000020E61000000100000001030000000100000005000000753BDDE44D5D4AC0346674B308F234C01479706212E649C05B353CFAB01535C03681ABB9AE014AC0BACB2C304FFA35C09743183CEA784AC094FC64E9A6D635C0753BDDE44D5D4AC0346674B308F234C0', 357, 357, 2128, -21.4816000000000003, -52.3260000000000005, 'S 21 28 53', 'O 52 19 33', 161, 124);
INSERT INTO bdc.mux_grid VALUES ('161/125', '0106000020E61000000100000001030000000100000005000000130E46A3F4784AC04399F3CCA3D635C0476DAEC2C2014AC0C7964E3249FA35C0A8CD03F69C1D4AC0A01769C8D5DE36C0756E9BD6CE944AC01D1A0E6330BB36C0130E46A3F4784AC04399F3CCA3D635C0', 358, 358, 2129, -22.3744000000000014, -52.5431999999999988, 'S 22 22 27', 'O 52 32 35', 161, 125);
INSERT INTO bdc.mux_grid VALUES ('161/126', '0106000020E61000000100000001030000000100000005000000AE87CDD9D9944AC0A046F4172DBB36C007B28E2AB21D4AC06C2FF770CFDE36C0BFB717DBCD394AC08A11C29849C337C0678D568AF5B04AC0BE28BF3FA79F37C0AE87CDD9D9944AC0A046F4172DBB36C0', 359, 359, 2132, -23.2669999999999995, -52.7622, 'S 23 16 01', 'O 52 45 44', 161, 126);
INSERT INTO bdc.mux_grid VALUES ('161/127', '0106000020E610000001000000010300000001000000050000003E460C3001B14AC0DE770BC4A39F37C0A06EB047E4394AC05CBAFDE342C337C022B8703E45564AC0B1F961CBA9A738C0C18FCC2662CD4AC034B76FAB0A8438C03E460C3001B14AC0DE770BC4A39F37C0', 360, 360, 2133, -24.1593000000000018, -52.9834000000000032, 'S 24 09 33', 'O 52 59 00', 161, 127);
INSERT INTO bdc.mux_grid VALUES ('161/128', '0106000020E610000001000000010300000001000000050000001C2C04766ECD4AC0A5C40AFD068438C0F2A690F05C564AC06AA243B5A2A738C017DC832107734AC0B4122986F58B39C04161F7A618EA4AC0ED34F0CD596839C01C2C04766ECD4AC0A5C40AFD068438C0', 361, 361, 2134, -25.0512000000000015, -53.2068000000000012, 'S 25 03 04', 'O 53 12 24', 161, 128);
INSERT INTO bdc.mux_grid VALUES ('161/129', '0106000020E61000000100000001030000000100000005000000BF9537A725EA4AC0B5CE99EA556839C02316AA2720734AC061E85A0AEE8B39C08FEA0CB517904AC0B3EF3AEA2B703AC02A6A9A341D074BC006D679CA934C3AC0BF9537A725EA4AC0B5CE99EA556839C0', 362, 362, 2135, -25.9429000000000016, -53.4324999999999974, 'S 25 56 34', 'O 53 25 56', 161, 129);
INSERT INTO bdc.mux_grid VALUES ('161/130', '0106000020E61000000100000001030000000100000005000000BDC8FCED2A074BC065DEC5AF8F4C3AC0961AD21E32904AC023E9120424703AC0C382AC5C7BAD4AC0F1BE80134C543BC0EA30D72B74244BC035B433BFB7303BC0BDC8FCED2A074BC065DEC5AF8F4C3AC0', 363, 363, 2137, -26.8341999999999992, -53.6606999999999985, 'S 26 50 03', 'O 53 39 38', 161, 130);
INSERT INTO bdc.mux_grid VALUES ('161/131', '0106000020E610000001000000010300000001000000050000002FA213A782244BC042B3866AB3303BC06ECED83A97AD4AC0E510FABD43543BC0B8F2CFB236CB4AC0CC891F1855383CC078C60A1F22424BC0282CACC4C4143CC02FA213A782244BC042B3866AB3303BC0', 364, 364, 2138, -27.7251000000000012, -53.8913999999999973, 'S 27 43 30', 'O 53 53 29', 161, 131);
INSERT INTO bdc.mux_grid VALUES ('161/132', '0106000020E610000001000000010300000001000000050000009324846531424BC0C58A3733C0143CC02906731754CB4AC02376D34D4C383CC0B932EA8C4EE94AC0FB2AE107461C3DC02451FBDA2B604BC09C3F45EDB9F83CC09324846531424BC0C58A3733C0143CC0', 365, 365, 2139, -28.6157000000000004, -54.1248999999999967, 'S 28 36 56', 'O 54 07 29', 161, 132);
INSERT INTO bdc.mux_grid VALUES ('161/133', '0106000020E61000000100000001030000000100000005000000864BCDF63B604BC01320031CB5F83CC014BA758B6DE94AC0CF15FFC23C1C3DC0195E0600C8074BC01CBB8EEB1D003EC08BEF5D6B967E4BC05EC5924496DC3DC0864BCDF63B604BC01320031CB5F83CC0', 366, 366, 2140, -29.5060000000000002, -54.3613, 'S 29 30 21', 'O 54 21 40', 161, 133);
INSERT INTO bdc.mux_grid VALUES ('161/134', '0106000020E61000000100000001030000000100000005000000BC596C67A77E4BC0766F413091DC3DC06B2A6BADE8074BC08573D32514003EC02BDDBC65A8264BC00EED3AC4DBE33EC0790CBE1F679D4BC0FFE8A8CE58C03EC0BC596C67A77E4BC0766F413091DC3DC0', 367, 367, 2142, -30.3958000000000013, -54.6007000000000033, 'S 30 23 44', 'O 54 36 02', 161, 134);
INSERT INTO bdc.mux_grid VALUES ('161/135', '0106000020E610000001000000010300000001000000050000005DBDC507799D4BC043BEC57353C03EC04D058BD8CA264BC07411E776D1E33EC048949561F5454BC095CA7A8A7EC73FC0594CD090A3BC4BC06377598700A43FC05DBDC507799D4BC043BEC57353C03EC0', 368, 368, 2144, -31.2852999999999994, -54.8434000000000026, 'S 31 17 06', 'O 54 50 36', 161, 135);
INSERT INTO bdc.mux_grid VALUES ('161/136', '0106000020E61000000100000001030000000100000005000000C1C27971B6BC4BC0DA5F1BE2FAA33FC07CE41FB219464BC0AD2F48AE73C73FC09C93E2E6B4654BC06278C596825540C0E0713CA651DC4BC07A10AF30C64340C0C1C27971B6BC4BC0DA5F1BE2FAA33FC0', 369, 369, 2145, -32.1743000000000023, -55.0893999999999977, 'S 32 10 27', 'O 55 05 22', 161, 136);
INSERT INTO bdc.mux_grid VALUES ('161/137', '0106000020E61000000100000001030000000100000005000000676C308D65DC4BC046B1D736C34340C07EB3652FDB654BC0447650DD7C5540C0842C203FED854BC04CA12F4937C740C06CE5EA9C77FC4BC04CDCB6A27DB540C0676C308D65DC4BC046B1D736C34340C0', 370, 370, 2146, -33.0628999999999991, -55.339100000000002, 'S 33 03 46', 'O 55 20 20', 161, 137);
INSERT INTO bdc.mux_grid VALUES ('161/138', '0106000020E610000001000000010300000001000000050000006D2EE9988CFC4BC0FA92727F7AB540C0CBE3ED9B15864BC0D2DD224031C740C08CD3E810A5A64BC0FC694DC9DC3841C02D1EE40D1C1D4CC0241F9D08262741C06D2EE9988CFC4BC0FA92727F7AB540C0', 371, 371, 2147, -33.9510000000000005, -55.5925000000000011, 'S 33 57 03', 'O 55 35 32', 161, 138);
INSERT INTO bdc.mux_grid VALUES ('162/102', '0106000020E61000000100000001030000000100000005000000F562D056CF9E48C0E6BC373A8211F4BF0B8772A52E2748C040261ACEEA4DF6BFB3AB29DE424048C00E5B579B245202C09D87878FE3B748C061266651F03301C0F562D056CF9E48C0E6BC373A8211F4BF', 372, 372, 2207, -1.79220000000000002, -48.8263999999999996, 'S 01 47 31', 'O 48 49 34', 162, 102);
INSERT INTO bdc.mux_grid VALUES ('162/103', '0106000020E6100000010000000103000000010000000500000069A03E3FE4B748C0D4FB01ADEE3301C0B256F84B444048C0C3A42930215202C0BD7BDD425D5948C0CBF73AA7437D09C074C52336FDD048C0DD4E1324115F08C069A03E3FE4B748C0D4FB01ADEE3301C0', 373, 373, 2208, -2.68829999999999991, -49.0223999999999975, 'S 02 41 17', 'O 49 01 20', 162, 103);
INSERT INTO bdc.mux_grid VALUES ('162/104', '0106000020E610000001000000010300000001000000050000001A2E6343FED048C02362E99F0E5F08C0BCB828635F5948C047B407913E7D09C047EC2A377F7248C0C8F04658275410C0A46165171EEA48C06B8F6FBF1E8A0FC01A2E6343FED048C02362E99F0E5F08C0', 374, 374, 2209, -3.58429999999999982, -49.2186000000000021, 'S 03 35 03', 'O 49 13 07', 162, 104);
INSERT INTO bdc.mux_grid VALUES ('162/105', '0106000020E61000000100000001030000000100000005000000554EAD821FEA48C089274D5A1B8A0FC00566F60A827248C068E973F6235410C001EF64DEAA8B48C038BDD50CA0E913C050D71B56480349C0936788C3895A13C0554EAD821FEA48C089274D5A1B8A0FC0', 375, 375, 2210, -4.48029999999999973, -49.4151000000000025, 'S 04 28 49', 'O 49 24 54', 162, 105);
INSERT INTO bdc.mux_grid VALUES ('162/106', '0106000020E6100000010000000103000000010000000500000000B119204A0349C0EF85AB9F875A13C0FBD00A67AE8B48C00537ABD29BE913C0704AA460E2A448C0E7E66221097F17C0732AB3197E1C49C0D33563EEF4EF16C000B119204A0349C0EF85AB9F875A13C0', 376, 376, 2212, -5.37619999999999987, -49.6118999999999986, 'S 05 22 34', 'O 49 36 42', 162, 106);
INSERT INTO bdc.mux_grid VALUES ('162/107', '0106000020E610000001000000010300000001000000050000006F414243801C49C0074D3458F2EF16C07EA3D69FE6A448C04DA6D90C047F17C0F5AFDCEB27BE48C0995CB3C45F141BC0E64D488FC13549C052030E104E851AC06F414243801C49C0074D3458F2EF16C0', 377, 377, 2213, -6.27210000000000001, -49.8091000000000008, 'S 06 16 19', 'O 49 48 32', 162, 107);
INSERT INTO bdc.mux_grid VALUES ('162/108', '0106000020E6100000010000000103000000010000000500000023BD7219C43549C0BDC04E064B851AC0F52FA7E32CBE48C087EE58D359141BC072E9F7B47DD748C05A28F423A1A91EC0A076C3EA144F49C08FFAE956921A1EC023BD7219C43549C0BDC04E064B851AC0', 378, 378, 2214, -7.16790000000000038, -50.0067999999999984, 'S 07 10 04', 'O 50 00 24', 162, 108);
INSERT INTO bdc.mux_grid VALUES ('162/109', '0106000020E610000001000000010300000001000000050000002238C3D6174F49C0ACC722D88E1A1EC0BEFEC16783D748C0845AE8529AA91EC00051F8F8E5F048C03EB23835651F21C0638AF9677A6849C0D1E8D577DFD720C02238C3D6174F49C0ACC722D88E1A1EC0', 379, 379, 2216, -8.06359999999999921, -50.2049999999999983, 'S 08 03 49', 'O 50 12 17', 162, 109);
INSERT INTO bdc.mux_grid VALUES ('162/110', '0106000020E61000000100000001030000000100000005000000ABBF39B77D6849C09A25157DDDD720C0A2A68769ECF048C0F8A4315B611F21C06ACE23FE620A49C02E8DA360ECE922C073E7D54BF48149C0D00D878268A222C0ABBF39B77D6849C09A25157DDDD720C0', 380, 380, 2218, -8.95919999999999916, -50.4037000000000006, 'S 08 57 33', 'O 50 24 13', 162, 110);
INSERT INTO bdc.mux_grid VALUES ('162/111', '0106000020E610000001000000010300000001000000050000009257F4FFF78149C050A4714B66A222C022339F2F6A0A49C057C93813E8E922C06DAB3815F72349C0B48D85A764B424C0DDCF8DE5849B49C0AD68BEDFE26C24C09257F4FFF78149C050A4714B66A222C0', 381, 381, 2219, -9.85479999999999912, -50.6032000000000011, 'S 09 51 17', 'O 50 36 11', 162, 111);
INSERT INTO bdc.mux_grid VALUES ('162/112', '0106000020E61000000100000001030000000100000005000000989E5C00899B49C0D28A3D6BE06C24C0EE622B0BFF2349C0676D98E45FB424C0479AAD9AA43D49C02273B79BCC7E26C0F0D5DE8F2EB549C08D905C224D3726C0989E5C00899B49C0D28A3D6BE06C24C0', 382, 382, 2220, -10.7501999999999995, -50.8034000000000034, 'S 10 45 00', 'O 50 48 12', 162, 112);
INSERT INTO bdc.mux_grid VALUES ('162/113', '0106000020E61000000100000001030000000100000005000000DC75661333B549C0D5F4386F4A3726C0AE210B59AD3D49C0F6F9EA60C77E26C08765FEF76D5749C0904D6CCD224928C0B6B959B2F3CE49C07048BADBA50128C0DC75661333B549C0D5F4386F4A3726C0', 383, 383, 2221, -11.6454000000000004, -51.0043000000000006, 'S 11 38 43', 'O 51 00 15', 162, 113);
INSERT INTO bdc.mux_grid VALUES ('162/114', '0106000020E61000000100000001030000000100000005000000A71DDBA0F8CE49C002DA9AE8A20128C0F4AE2683775749C067A022181D4928C034D106A5557149C0BBF4F8CA65132AC0E73FBBC2D6E849C0572E719BEBCB29C0A71DDBA0F8CE49C002DA9AE8A20128C0', 384, 384, 2223, -12.5404999999999998, -51.2062000000000026, 'S 12 32 25', 'O 51 12 22', 162, 114);
INSERT INTO bdc.mux_grid VALUES ('162/115', '0106000020E610000001000000010300000001000000050000007450B21EDCE849C0A294D966E8CB29C0E701CB01607149C0B28350985F132AC015576D295E8B49C0E9F2952094DD2BC0A2A55446DA024AC0DA031FEF1C962BC07450B21EDCE849C0A294D966E8CB29C0', 385, 385, 2224, -13.4354999999999993, -51.4089999999999989, 'S 13 26 07', 'O 51 24 32', 162, 115);
INSERT INTO bdc.mux_grid VALUES ('162/116', '0106000020E6100000010000000103000000010000000500000041FD7A12E0024AC0B6FF6D7719962BC0320C155D698B49C08552666D8DDD2BC0027D1F1E8AA549C0EF471B58ACA72DC0126E85D3001D4AC021F5226238602DC041FD7A12E0024AC0B6FF6D7719962BC0', 386, 386, 2225, -14.3302999999999994, -51.6129000000000033, 'S 14 19 49', 'O 51 36 46', 162, 116);
INSERT INTO bdc.mux_grid VALUES ('162/117', '0106000020E610000001000000010300000001000000050000001F63D512071D4AC07F8F90A534602DC044A56E2E96A549C05EB1F120A5A72DC074AFE12EDCBF49C02663B5F8AC712FC0506D48134D374AC04741547D3C2A2FC01F63D512071D4AC07F8F90A534602DC0', 387, 387, 2226, -15.2249999999999996, -51.8177999999999983, 'S 15 13 29', 'O 51 49 04', 162, 117);
INSERT INTO bdc.mux_grid VALUES ('162/118', '0106000020E61000000100000001030000000100000005000000F06D00C953374AC0EEC8EF79382A2FC0D9011F22E9BF49C092D6D039A5712FC010A9F41B57DA49C0F4534943CA9D30C02815D6C2C1514AC023CD58E3137A30C0F06D00C953374AC0EEC8EF79382A2FC0', 388, 388, 2229, -16.1193999999999988, -52.0240000000000009, 'S 16 07 09', 'O 52 01 26', 162, 118);
INSERT INTO bdc.mux_grid VALUES ('162/119', '0106000020E61000000100000001030000000100000005000000F85D7CF2C8514AC092B52FBD117A30C0C1C6F0F864DA49C02AD4EF1DC69D30C0719FD2BBFDF449C0956044C1B08231C0A8365EB5616C4AC0FD418460FC5E31C0F85D7CF2C8514AC092B52FBD117A30C0', 389, 389, 2230, -17.0137, -52.2314999999999969, 'S 17 00 49', 'O 52 13 53', 162, 119);
INSERT INTO bdc.mux_grid VALUES ('162/120', '0106000020E610000001000000010300000001000000050000007BE8C462696C4AC0D9CABF14FA5E31C0F8ECEF890CF549C06151CE53AC8231C0B19906FDD20F4AC0177FD834896732C03295DBD52F874AC090F8C9F5D64332C07BE8C462696C4AC0D9CABF14FA5E31C0', 390, 390, 2231, -17.9076999999999984, -52.4403000000000006, 'S 17 54 27', 'O 52 26 25', 162, 120);
INSERT INTO bdc.mux_grid VALUES ('162/121', '0106000020E610000001000000010300000001000000050000007034250538874AC032932D83D44332C0D6E141C4E20F4AC0EE5DE27C846732C02B8F20E8D92A4AC03D6C7DDA524C33C0C5E103292FA24AC081A1C8E0A22833C07034250538874AC032932D83D44332C0', 391, 391, 2232, -18.8016000000000005, -52.6505999999999972, 'S 18 48 05', 'O 52 39 02', 162, 121);
INSERT INTO bdc.mux_grid VALUES ('162/122', '0106000020E61000000100000001030000000100000005000000EB47A8DE37A24AC0563AFE45A02833C0DA7C1AB1EA2A4AC083B472D54D4C33C05722C9A115464AC064DF59EC0C3134C067ED56CF62BD4AC03665E55C5F0D34C0EB47A8DE37A24AC0563AFE45A02833C0', 392, 392, 2234, -19.6951000000000001, -52.8624000000000009, 'S 19 41 42', 'O 52 51 44', 162, 122);
INSERT INTO bdc.mux_grid VALUES ('162/123', '0106000020E610000001000000010300000001000000050000005CB628106CBD4AC039C47B985C0D34C09EA9D07527464AC064ED7197073134C01117F86C89614AC06E8E01A2B61535C0CF235007CED84AC042650BA30BF234C05CB628106CBD4AC039C47B985C0D34C0', 393, 393, 2235, -20.5884999999999998, -53.0758999999999972, 'S 20 35 18', 'O 53 04 33', 162, 123);
INSERT INTO bdc.mux_grid VALUES ('162/124', '0106000020E61000000100000001030000000100000005000000FCA282D8D7D84AC0F36574B308F234C099E015569C614AC019353CFAB01535C0BDE850AD387D4AC08ACB2C304FFA35C01EABBD2F74F44AC063FC64E9A6D635C0FCA282D8D7D84AC0F36574B308F234C0', 394, 394, 2236, -21.4816000000000003, -53.2912000000000035, 'S 21 28 53', 'O 53 17 28', 162, 124);
INSERT INTO bdc.mux_grid VALUES ('162/125', '0106000020E610000001000000010300000001000000050000008175EB967EF44AC01999F3CCA3D635C0B4D453B64C7D4AC09B964E3249FA35C02635A9E926994AC0051869C8D5DE36C0F5D540CA58104BC0821A0E6330BB36C08175EB967EF44AC01999F3CCA3D635C0', 395, 395, 2237, -22.3744000000000014, -53.5082999999999984, 'S 22 22 27', 'O 53 30 29', 162, 125);
INSERT INTO bdc.mux_grid VALUES ('162/126', '0106000020E6100000010000000103000000010000000500000045EF72CD63104BC0FF46F4172DBB36C09D19341E3C994AC0CA2FF770CFDE36C0381FBDCE57B54AC0F810C29849C337C0E0F4FB7D7F2C4BC02F28BF3FA79F37C045EF72CD63104BC0FF46F4172DBB36C0', 396, 396, 2240, -23.2669999999999995, -53.7274000000000029, 'S 23 16 01', 'O 53 43 38', 162, 126);
INSERT INTO bdc.mux_grid VALUES ('162/127', '0106000020E61000000100000001030000000100000005000000BDADB1238B2C4BC04C770BC4A39F37C020D6553B6EB54AC0C8B9FDE342C337C0B31F1632CFD14AC0ADF961CBA9A738C050F7711AEC484BC030B76FAB0A8438C0BDADB1238B2C4BC04C770BC4A39F37C0', 397, 397, 2241, -24.1593000000000018, -53.948599999999999, 'S 24 09 33', 'O 53 56 54', 162, 127);
INSERT INTO bdc.mux_grid VALUES ('162/128', '0106000020E61000000100000001030000000100000005000000DE93A969F8484BC092C40AFD068438C06F0E36E4E6D14AC06BA243B5A2A738C0A343291591EE4AC045132986F58B39C012C99C9AA2654BC06A35F0CD596839C0DE93A969F8484BC092C40AFD068438C0', 398, 398, 2242, -25.0512000000000015, -54.1719000000000008, 'S 25 03 04', 'O 54 10 18', 162, 128);
INSERT INTO bdc.mux_grid VALUES ('162/129', '0106000020E610000001000000010300000001000000050000004FFDDC9AAF654BC043CF99EA556839C0B47D4F1BAAEE4AC0EFE85A0AEE8B39C01252B2A8A10B4BC0D1EF3AEA2B703AC0ADD13F28A7824BC025D679CA934C3AC04FFDDC9AAF654BC043CF99EA556839C0', 399, 399, 2244, -25.9429000000000016, -54.3975999999999971, 'S 25 56 34', 'O 54 23 51', 162, 129);
INSERT INTO bdc.mux_grid VALUES ('162/130', '0106000020E610000001000000010300000001000000050000005330A2E1B4824BC080DEC5AF8F4C3AC02D827712BC0B4BC03DE9120424703AC04AEA515005294BC09ABE80134C543BC071987C1FFE9F4BC0DFB333BFB7303BC05330A2E1B4824BC080DEC5AF8F4C3AC0', 400, 400, 2245, -26.8341999999999992, -54.6257999999999981, 'S 26 50 03', 'O 54 37 32', 162, 130);
INSERT INTO bdc.mux_grid VALUES ('162/131', '0106000020E61000000100000001030000000100000005000000E409B99A0CA04BC0DEB2866AB3303BC0DE357E2E21294BC09410FABD43543BC0295A75A6C0464BC08A891F1855383CC02F2EB012ACBD4BC0D42BACC4C4143CC0E409B99A0CA04BC0DEB2866AB3303BC0', 401, 401, 2246, -27.7251000000000012, -54.8566000000000003, 'S 27 43 30', 'O 54 51 23', 162, 131);
INSERT INTO bdc.mux_grid VALUES ('162/132', '0106000020E610000001000000010300000001000000050000000B8C2959BBBD4BC0838A3733C0143CC09E6D180BDE464BC0E075D34D4C383CC0429A8F80D8644BC0462BE107461C3DC0ADB8A0CEB5DB4BC0E93F45EDB9F83CC00B8C2959BBBD4BC0838A3733C0143CC0', 402, 402, 2247, -28.6157000000000004, -55.0900999999999996, 'S 28 36 56', 'O 55 05 24', 162, 132);
INSERT INTO bdc.mux_grid VALUES ('162/133', '0106000020E6100000010000000103000000010000000500000061B372EAC5DB4BC04920031CB5F83CC063211B7FF7644BC02C16FFC23C1C3DC059C5ABF351834BC006BB8EEB1D003EC05557035F20FA4BC023C5924496DC3DC061B372EAC5DB4BC04920031CB5F83CC0', 403, 403, 2249, -29.5060000000000002, -55.3265000000000029, 'S 29 30 21', 'O 55 19 35', 162, 133);
INSERT INTO bdc.mux_grid VALUES ('162/134', '0106000020E6100000010000000103000000010000000500000047C1115B31FA4BC04E6F413091DC3DC0F69110A172834BC05C73D32514003EC0B744625932A24BC0F4EC3AC4DBE33EC007746313F1184CC0E4E8A8CE58C03EC047C1115B31FA4BC04E6F413091DC3DC0', 404, 404, 2250, -30.3958000000000013, -55.5658999999999992, 'S 30 23 44', 'O 55 33 57', 162, 134);
INSERT INTO bdc.mux_grid VALUES ('162/135', '0106000020E6100000010000000103000000010000000500000025256BFB02194CC018BEC57353C03EC0CF6C30CC54A24BC05B11E776D1E33EC0CCFB3A557FC14BC08CCA7A8A7EC73FC023B475842D384CC04977598700A43FC025256BFB02194CC018BEC57353C03EC0', 405, 405, 2252, -31.2852999999999994, -55.8085000000000022, 'S 31 17 06', 'O 55 48 30', 162, 135);
INSERT INTO bdc.mux_grid VALUES ('162/136', '0106000020E61000000100000001030000000100000005000000902A1F6540384CC0BA5F1BE2FAA33FC04B4CC5A5A3C14BC08F2F48AE73C73FC061FB87DA3EE14BC02C78C596825540C0A5D9E199DB574CC04210AF30C64340C0902A1F6540384CC0BA5F1BE2FAA33FC0', 406, 406, 2254, -32.1743000000000023, -56.0546000000000006, 'S 32 10 27', 'O 56 03 16', 162, 136);
INSERT INTO bdc.mux_grid VALUES ('162/137', '0106000020E6100000010000000103000000010000000500000002D4D580EF574CC016B1D736C34340C0191B0B2365E14BC0147650DD7C5540C02194C53277014CC022A12F4937C740C0094D909001784CC024DCB6A27DB540C002D4D580EF574CC016B1D736C34340C0', 407, 407, 2255, -33.0628999999999991, -56.3042000000000016, 'S 33 03 46', 'O 56 18 15', 162, 137);
INSERT INTO bdc.mux_grid VALUES ('162/138', '0106000020E6100000010000000103000000010000000500000048968E8C16784CC0C492727F7AB540C01C4B938F9F014CC0B4DD224031C740C0F03A8E042F224CC0246A4DC9DC3841C01C868901A6984CC0361F9D08262741C048968E8C16784CC0C492727F7AB540C0', 408, 408, 2256, -33.9510000000000005, -56.5576000000000008, 'S 33 57 03', 'O 56 33 27', 162, 138);
INSERT INTO bdc.mux_grid VALUES ('162/141', '0106000020E610000001000000010300000001000000050000005591E7509FDB4CC0788CD89D430A42C08A4D600A69654CC0882A60B1F01B42C037597CEE9B874CC0CC78DBFA6B8D42C0029D0335D2FD4CC0BEDA53E7BE7B42C05591E7509FDB4CC0788CD89D430A42C0', 409, 409, 2260, -36.6124999999999972, -57.3425999999999974, 'S 36 36 45', 'O 57 20 33', 162, 141);
INSERT INTO bdc.mux_grid VALUES ('162/142', '0106000020E610000001000000010300000001000000050000008EFB2532ECFD4CC0DC5A7E04BB7B42C0AA874AE8CD874CC03C37D181648D42C0FD1C1C889CAA4CC0D838B46BCEFE42C0E190F7D1BA204DC0795C61EE24ED42C08EFB2532ECFD4CC0DC5A7E04BB7B42C0', 410, 410, 2261, -37.4986000000000033, -57.6133000000000024, 'S 37 29 55', 'O 57 36 47', 162, 142);
INSERT INTO bdc.mux_grid VALUES ('163/101', '0106000020E610000001000000010300000001000000050000003BE6CF60470149C02576E2565CECD6BFF40AF445A68948C0CBCE818906DEDFBF1FA317DDB7A248C0F4FDAB51EE4DF6BF657EF3F7581A49C0C92704C58311F4BF3BE6CF60470149C02576E2565CECD6BF', 411, 411, 2317, -0.896100000000000008, -49.5955999999999975, 'S 00 53 45', 'O 49 35 44', 163, 101);
INSERT INTO bdc.mux_grid VALUES ('163/102', '0106000020E610000001000000010300000001000000050000009FCA754A591A49C006BD373A8211F4BFABEE1799B8A248C088261ACEEA4DF6BF5213CFD1CCBB48C0135B579B245202C046EF2C836D3349C04F266651F03301C09FCA754A591A49C006BD373A8211F4BF', 412, 412, 2318, -1.79220000000000002, -49.7914999999999992, 'S 01 47 31', 'O 49 47 29', 163, 102);
INSERT INTO bdc.mux_grid VALUES ('163/103', '0106000020E610000001000000010300000001000000050000000C08E4326E3349C0CCFB01ADEE3301C04DBE9D3FCEBB48C0CBA42930215202C057E38236E7D448C095F73AA7437D09C0172DC929874C49C0964E1324115F08C00C08E4326E3349C0CCFB01ADEE3301C0', 413, 413, 2319, -2.68829999999999991, -49.9876000000000005, 'S 02 41 17', 'O 49 59 15', 163, 103);
INSERT INTO bdc.mux_grid VALUES ('163/104', '0106000020E61000000100000001030000000100000005000000B9950837884C49C0DB61E99F0E5F08C05D20CE56E9D448C000B407913E7D09C0E853D02A09EE48C0A6F04658275410C045C90A0BA86549C0278F6FBF1E8A0FC0B9950837884C49C0DB61E99F0E5F08C0', 414, 414, 2320, -3.58429999999999982, -50.183799999999998, 'S 03 35 03', 'O 50 11 01', 163, 104);
INSERT INTO bdc.mux_grid VALUES ('163/105', '0106000020E6100000010000000103000000010000000500000002B65276A96549C027274D5A1B8A0FC0A1CD9BFE0BEE48C04DE973F6235410C09D560AD2340749C05EBDD50CA0E913C0FE3EC149D27E49C0A56788C3895A13C002B65276A96549C027274D5A1B8A0FC0', 415, 415, 2322, -4.48029999999999973, -50.3802999999999983, 'S 04 28 49', 'O 50 22 48', 163, 105);
INSERT INTO bdc.mux_grid VALUES ('163/106', '0106000020E61000000100000001030000000100000005000000A718BF13D47E49C00A86AB9F875A13C0A438B05A380749C01F37ABD29BE913C018B249546C2049C040E76221097F17C01C92580D089849C02B3663EEF4EF16C0A718BF13D47E49C00A86AB9F875A13C0', 416, 416, 2323, -5.37619999999999987, -50.5771000000000015, 'S 05 22 34', 'O 50 34 37', 163, 106);
INSERT INTO bdc.mux_grid VALUES ('163/107', '0106000020E6100000010000000103000000010000000500000009A9E7360A9849C0724D3458F2EF16C0180B7C93702049C0B9A6D90C047F17C08C1782DFB13949C0835CB3C45F141BC07DB5ED824BB149C03D030E104E851AC009A9E7360A9849C0724D3458F2EF16C0', 417, 417, 2324, -6.27210000000000001, -50.7742999999999967, 'S 06 16 19', 'O 50 46 27', 163, 107);
INSERT INTO bdc.mux_grid VALUES ('163/108', '0106000020E61000000100000001030000000100000005000000C124180D4EB149C09DC04E064B851AC0A4974CD7B63949C053EE58D359141BC022519DA8075349C02A28F423A1A91EC03FDE68DE9ECA49C073FAE956921A1EC0C124180D4EB149C09DC04E064B851AC0', 418, 418, 2325, -7.16790000000000038, -50.971899999999998, 'S 07 10 04', 'O 50 58 18', 163, 108);
INSERT INTO bdc.mux_grid VALUES ('163/109', '0106000020E61000000100000001030000000100000005000000C59F68CAA1CA49C08AC722D88E1A1EC06066675B0D5349C0605AE8529AA91EC0A2B89DEC6F6C49C02BB23835651F21C007F29E5B04E449C0BEE8D577DFD720C0C59F68CAA1CA49C08AC722D88E1A1EC0', 419, 419, 2328, -8.06359999999999921, -51.1700999999999979, 'S 08 03 49', 'O 51 10 12', 163, 109);
INSERT INTO bdc.mux_grid VALUES ('163/110', '0106000020E610000001000000010300000001000000050000003C27DFAA07E449C09225157DDDD720C0550E2D5D766C49C0DBA4315B611F21C02036C9F1EC8549C0528DA360ECE922C0074F7B3F7EFD49C0080E878268A222C03C27DFAA07E449C09225157DDDD720C0', 420, 420, 2329, -8.95919999999999916, -51.3688999999999965, 'S 08 57 33', 'O 51 22 08', 163, 110);
INSERT INTO bdc.mux_grid VALUES ('163/111', '0106000020E6100000010000000103000000010000000500000034BF99F381FD49C07FA4714B66A222C0C39A4423F48549C087C93813E8E922C00F13DE08819F49C0E48D85A764B424C07E3733D90E174AC0DD68BEDFE26C24C034BF99F381FD49C07FA4714B66A222C0', 421, 421, 2330, -9.85479999999999912, -51.5683000000000007, 'S 09 51 17', 'O 51 34 05', 163, 111);
INSERT INTO bdc.mux_grid VALUES ('163/112', '0106000020E610000001000000010300000001000000050000003E0602F412174AC0018B3D6BE06C24C095CAD0FE889F49C0936D98E45FB424C0EE01538E2EB949C04E73B79BCC7E26C0963D8483B8304AC0BC905C224D3726C03E0602F412174AC0018B3D6BE06C24C0', 422, 422, 2331, -10.7501999999999995, -51.7685000000000031, 'S 10 45 00', 'O 51 46 06', 163, 112);
INSERT INTO bdc.mux_grid VALUES ('163/113', '0106000020E6100000010000000103000000010000000500000080DD0B07BD304AC004F5386F4A3726C05189B04C37B949C025FAEA60C77E26C02ACDA3EBF7D249C0BF4D6CCD224928C05821FFA57D4A4AC0A048BADBA50128C080DD0B07BD304AC004F5386F4A3726C0', 423, 423, 2333, -11.6454000000000004, -51.9694999999999965, 'S 11 38 43', 'O 51 58 10', 163, 113);
INSERT INTO bdc.mux_grid VALUES ('163/114', '0106000020E610000001000000010300000001000000050000005B858094824A4AC027DA9AE8A20128C0A816CC7601D349C08CA022181D4928C0E138AC98DFEC49C061F4F8CA65132AC094A760B660644AC0FC2D719BEBCB29C05B858094824A4AC027DA9AE8A20128C0', 424, 424, 2334, -12.5404999999999998, -52.1713000000000022, 'S 12 32 25', 'O 52 10 16', 163, 114);
INSERT INTO bdc.mux_grid VALUES ('163/115', '0106000020E6100000010000000103000000010000000500000016B8571266644AC04D94D966E8CB29C0896970F5E9EC49C05D8350985F132AC0BFBE121DE8064AC016F3952094DD2BC04B0DFA39647E4AC006041FEF1C962BC016B8571266644AC04D94D966E8CB29C0', 425, 425, 2335, -13.4354999999999993, -52.3742000000000019, 'S 13 26 07', 'O 52 22 26', 163, 115);
INSERT INTO bdc.mux_grid VALUES ('163/116', '0106000020E61000000100000001030000000100000005000000E56420066A7E4AC0E5FF6D7719962BC0D773BA50F3064AC0B752666D8DDD2BC0A6E4C41114214AC021481B58ACA72DC0B5D52AC78A984AC050F5226238602DC0E56420066A7E4AC0E5FF6D7719962BC0', 426, 426, 2336, -14.3302999999999994, -52.578000000000003, 'S 14 19 49', 'O 52 34 40', 163, 116);
INSERT INTO bdc.mux_grid VALUES ('163/117', '0106000020E61000000100000001030000000100000005000000BBCA7A0691984AC0B58F90A534602DC0020D142220214AC07FB1F120A5A72DC02A178722663B4AC0C662B5F8AC712FC0E4D4ED06D7B24AC0FC40547D3C2A2FC0BBCA7A0691984AC0B58F90A534602DC0', 427, 427, 2337, -15.2249999999999996, -52.7830000000000013, 'S 15 13 29', 'O 52 46 58', 163, 117);
INSERT INTO bdc.mux_grid VALUES ('163/118', '0106000020E6100000010000000103000000010000000500000089D5A5BCDDB24AC0A0C8EF79382A2FC09369C415733B4AC02FD6D039A5712FC0D3109A0FE1554AC003544943CA9D30C0C97C7BB64BCD4AC03CCD58E3137A30C089D5A5BCDDB24AC0A0C8EF79382A2FC0', 428, 428, 2340, -16.1193999999999988, -52.9891999999999967, 'S 16 07 09', 'O 52 59 20', 163, 118);
INSERT INTO bdc.mux_grid VALUES ('163/119', '0106000020E6100000010000000103000000010000000500000089C521E652CD4AC0B0B52FBD117A30C0752E96ECEE554AC03ED4EF1DC69D30C0250778AF87704AC0A96044C1B08231C0389E03A9EBE74AC01B428460FC5E31C089C521E652CD4AC0B0B52FBD117A30C0', 429, 429, 2341, -17.0137, -53.1965999999999966, 'S 17 00 49', 'O 53 11 47', 163, 119);
INSERT INTO bdc.mux_grid VALUES ('163/120', '0106000020E6100000010000000103000000010000000500000023506A56F3E74AC0F1CABF14FA5E31C0C454957D96704AC06D51CE53AC8231C07C01ACF05C8B4AC0237FD834896732C0DCFC80C9B9024BC0A7F8C9F5D64332C023506A56F3E74AC0F1CABF14FA5E31C0', 430, 430, 2342, -17.9076999999999984, -53.4054000000000002, 'S 17 54 27', 'O 53 24 19', 163, 120);
INSERT INTO bdc.mux_grid VALUES ('163/121', '0106000020E61000000100000001030000000100000005000000289CCAF8C1024BC045932D83D44332C06B49E7B76C8B4AC00C5EE27C846732C0B9F6C5DB63A64AC01B6C7DDA524C33C07649A91CB91D4BC053A1C8E0A22833C0289CCAF8C1024BC045932D83D44332C0', 431, 431, 2344, -18.8016000000000005, -53.6156999999999968, 'S 18 48 05', 'O 53 36 56', 163, 121);
INSERT INTO bdc.mux_grid VALUES ('163/122', '0106000020E61000000100000001030000000100000005000000CFAF4DD2C11D4BC0173AFE45A02833C057E4BFA474A64AC065B472D54D4C33C0CC896E959FC14AC007DF59EC0C3134C04355FCC2EC384BC0B964E55C5F0D34C0CFAF4DD2C11D4BC0173AFE45A02833C0', 432, 432, 2345, -19.6951000000000001, -53.8275999999999968, 'S 19 41 42', 'O 53 49 39', 163, 122);
INSERT INTO bdc.mux_grid VALUES ('163/123', '0106000020E61000000100000001030000000100000005000000DC1DCE03F6384BC0D7C37B985C0D34C063117669B1C14AC0EFEC7197073134C0E57E9D6013DD4AC0778E01A2B61535C05E8BF5FA57544BC060650BA30BF234C0DC1DCE03F6384BC0D7C37B985C0D34C0', 433, 433, 2346, -20.5884999999999998, -54.0411000000000001, 'S 20 35 18', 'O 54 02 27', 163, 123);
INSERT INTO bdc.mux_grid VALUES ('163/124', '0106000020E61000000100000001030000000100000005000000D10A28CC61544BC0FE6574B308F234C02A48BB4926DD4AC038353CFAB01535C04E50F6A0C2F84AC0A7CB2C304FFA35C0F4126323FE6F4BC06DFC64E9A6D635C0D10A28CC61544BC0FE6574B308F234C0', 434, 434, 2347, -21.4816000000000003, -54.2563000000000031, 'S 21 28 53', 'O 54 15 22', 163, 124);
INSERT INTO bdc.mux_grid VALUES ('163/125', '0106000020E6100000010000000103000000010000000500000082DD908A08704BC01799F3CCA3D635C02C3CF9A9D6F84AC0C1964E3249FA35C09F9C4EDDB0144BC02A1869C8D5DE36C0F53DE6BDE28B4BC07F1A0E6330BB36C082DD908A08704BC01799F3CCA3D635C0', 435, 435, 2349, -22.3744000000000014, -54.4735000000000014, 'S 22 22 27', 'O 54 28 24', 163, 125);
INSERT INTO bdc.mux_grid VALUES ('163/126', '0106000020E61000000100000001030000000100000005000000185718C1ED8B4BC00A47F4172DBB36C02B81D911C6144BC0E92FF770CFDE36C0D48662C2E1304BC09611C29849C337C0C15CA17109A84BC0B828BF3FA79F37C0185718C1ED8B4BC00A47F4172DBB36C0', 436, 436, 2351, -23.2669999999999995, -54.6925000000000026, 'S 23 16 01', 'O 54 41 33', 163, 126);
INSERT INTO bdc.mux_grid VALUES ('163/127', '0106000020E610000001000000010300000001000000050000006115571715A84BC0E8770BC4A39F37C0C33DFB2EF8304BC065BAFDE342C337C04687BB25594D4BC0CAF961CBA9A738C0E45E170E76C44BC04DB76FAB0A8438C06115571715A84BC0E8770BC4A39F37C0', 437, 437, 2352, -24.1593000000000018, -54.9136999999999986, 'S 24 09 33', 'O 54 54 49', 163, 127);
INSERT INTO bdc.mux_grid VALUES ('163/128', '0106000020E61000000100000001030000000100000005000000A4FB4E5D82C44BC0A0C40AFD068438C03276DBD7704D4BC078A243B5A2A738C067ABCE081B6A4BC051132986F58B39C0DA30428E2CE14BC07A35F0CD596839C0A4FB4E5D82C44BC0A0C40AFD068438C0', 438, 438, 2354, -25.0512000000000015, -55.1370999999999967, 'S 25 03 04', 'O 55 08 13', 163, 128);
INSERT INTO bdc.mux_grid VALUES ('163/129', '0106000020E61000000100000001030000000100000005000000D364828E39E14BC066CF99EA556839C038E5F40E346A4BC012E95A0AEE8B39C085B9579C2B874BC073EF3AEA2B703AC02139E51B31FE4BC0C7D579CA934C3AC0D364828E39E14BC066CF99EA556839C0', 439, 439, 2355, -25.9429000000000016, -55.3628, 'S 25 56 34', 'O 55 21 46', 163, 129);
INSERT INTO bdc.mux_grid VALUES ('163/130', '0106000020E610000001000000010300000001000000050000001D9847D53EFE4BC009DEC5AF8F4C3AC0B2E91C0646874BC0D9E8120424703AC0F051F7438FA44BC037BF80134C543BC05C002213881B4CC065B433BFB7303BC01D9847D53EFE4BC009DEC5AF8F4C3AC0', 440, 440, 2356, -26.8341999999999992, -55.5910000000000011, 'S 26 50 03', 'O 55 35 27', 163, 130);
INSERT INTO bdc.mux_grid VALUES ('163/131', '0106000020E6100000010000000103000000010000000500000072715E8E961B4CC082B3866AB3303BC0B39D2322ABA44BC02411FABD43543BC0EDC11A9A4AC24BC09A891F1855383CC0AE95550636394CC0F92BACC4C4143CC072715E8E961B4CC082B3866AB3303BC0', 441, 441, 2357, -27.7251000000000012, -55.8216999999999999, 'S 27 43 30', 'O 55 49 18', 163, 131);
INSERT INTO bdc.mux_grid VALUES ('163/132', '0106000020E61000000100000001030000000100000005000000D3F3CE4C45394CC0908A3733C0143CC023D5BDFE67C24BC00276D34D4C383CC0B501357462E04BC0E92AE107461C3DC0662046C23F574CC0783F45EDB9F83CC0D3F3CE4C45394CC0908A3733C0143CC0', 442, 442, 2359, -28.6157000000000004, -56.0551999999999992, 'S 28 36 56', 'O 56 03 18', 163, 132);
INSERT INTO bdc.mux_grid VALUES ('163/133', '0106000020E61000000100000001030000000100000005000000DF1A18DE4F574CC0E61F031CB5F83CC02689C07281E04BC0B615FFC23C1C3DC01B2D51E7DBFE4BC092BA8EEB1D003EC0D3BEA852AA754CC0C2C4924496DC3DC0DF1A18DE4F574CC0E61F031CB5F83CC0', 443, 443, 2360, -29.5060000000000002, -56.2916000000000025, 'S 29 30 21', 'O 56 17 29', 163, 133);
INSERT INTO bdc.mux_grid VALUES ('163/134', '0106000020E610000001000000010300000001000000050000000F29B74EBB754CC0D56E413091DC3DC079F9B594FCFE4BC0F772D32514003EC039AC074DBC1D4CC091EC3AC4DBE33EC0CFDB08077B944CC06EE8A8CE58C03EC00F29B74EBB754CC0D56E413091DC3DC0', 444, 444, 2361, -30.3958000000000013, -56.5309999999999988, 'S 30 23 44', 'O 56 31 51', 163, 134);
INSERT INTO bdc.mux_grid VALUES ('163/135', '0106000020E610000001000000010300000001000000050000009C8C10EF8C944CC0B9BDC57353C03EC08DD4D5BFDE1D4CC0E610E776D1E33EC09B63E048093D4CC098CA7A8A7EC73FC0AD1B1B78B7B34CC06977598700A43FC09C8C10EF8C944CC0B9BDC57353C03EC0', 445, 445, 2364, -31.2852999999999994, -56.7736999999999981, 'S 31 17 06', 'O 56 46 25', 163, 135);
INSERT INTO bdc.mux_grid VALUES ('163/136', '0106000020E61000000100000001030000000100000005000000DB91C458CAB34CC0EE5F1BE2FAA33FC021B46A992D3D4CC0982F48AE73C73FC037632DCEC85C4CC03078C596825540C0F240878D65D34CC05A10AF30C64340C0DB91C458CAB34CC0EE5F1BE2FAA33FC0', 446, 446, 2365, -32.1743000000000023, -57.0197000000000003, 'S 32 10 27', 'O 57 01 11', 163, 136);
INSERT INTO bdc.mux_grid VALUES ('163/137', '0106000020E61000000100000001030000000100000005000000AD3B7B7479D34CC020B1D736C34340C0C582B016EF5C4CC0207650DD7C5540C0DFFB6A26017D4CC06CA12F4937C740C0C7B435848BF34CC06CDCB6A27DB540C0AD3B7B7479D34CC020B1D736C34340C0', 447, 447, 2366, -33.0628999999999991, -57.2693999999999974, 'S 33 03 46', 'O 57 16 09', 163, 137);
INSERT INTO bdc.mux_grid VALUES ('163/138', '0106000020E6100000010000000103000000010000000500000000FE3380A0F34CC01093727F7AB540C019B33883297D4CC0F4DD224031C740C0C9A233F8B89D4CC0E6694DC9DC3841C0AFED2EF52F144DC0021F9D08262741C000FE3380A0F34CC01093727F7AB540C0', 448, 448, 2367, -33.9510000000000005, -57.5227999999999966, 'S 33 57 03', 'O 57 31 21', 163, 138);
INSERT INTO bdc.mux_grid VALUES ('163/140', '0106000020E61000000100000001030000000100000005000000F11E4C3471354DC0EA7FB44DBB9841C0953C793224BF4CC086D362C76BAA41C0A311ACA2C3E04CC09CD829C6F71B42C0FFF37EA410574DC000857B4C470A42C0F11E4C3471354DC0EA7FB44DBB9841C0', 449, 449, 2369, -35.7257999999999996, -58.0416999999999987, 'S 35 43 33', 'O 58 02 30', 163, 140);
INSERT INTO bdc.mux_grid VALUES ('163/141', '0106000020E6100000010000000103000000010000000500000098F88C4429574DC0508CD89D430A42C059B505FEF2E04CC04C2A60B1F01B42C02BC121E225034DC00E79DBFA6B8D42C06C04A9285C794DC014DB53E7BE7B42C098F88C4429574DC0508CD89D430A42C0', 450, 450, 2370, -36.6124999999999972, -58.3078000000000003, 'S 36 36 45', 'O 58 18 27', 163, 141);
INSERT INTO bdc.mux_grid VALUES ('163/142', '0106000020E610000001000000010300000001000000050000004763CB2576794DC0265B7E04BB7B42C064EFEFDB57034DC08637D181648D42C0B684C17B26264DC02239B46BCEFE42C099F89CC5449C4DC0C45C61EE24ED42C04763CB2576794DC0265B7E04BB7B42C0', 451, 451, 2372, -37.4986000000000033, -58.5784999999999982, 'S 37 29 55', 'O 58 34 42', 163, 142);
INSERT INTO bdc.mux_grid VALUES ('163/143', '0106000020E610000001000000010300000001000000050000001200BE35609C4DC0D86E12D420ED42C007C5FF3D5B264DC02C542288C6FE42C05EAC2169CE494DC02C3C7A5F1E7043C068E7DF60D3BF4DC0DA566AAB785E43C01200BE35609C4DC0D86E12D420ED42C0', 452, 452, 2373, -38.3841999999999999, -58.8541000000000025, 'S 38 23 03', 'O 58 51 14', 163, 143);
INSERT INTO bdc.mux_grid VALUES ('164/101', '0106000020E61000000100000001030000000100000005000000DF4D7554D17C49C0A075E2565CECD6BF99729939300549C053CE818906DEDFBFC30ABDD0411E49C01BFEAB51EE4DF6BF0AE698EBE29549C0EE2704C58311F4BFDF4D7554D17C49C0A075E2565CECD6BF', 453, 453, 2432, -0.896100000000000008, -50.5608000000000004, 'S 00 53 45', 'O 50 33 38', 164, 101);
INSERT INTO bdc.mux_grid VALUES ('164/102', '0106000020E6100000010000000103000000010000000500000042321B3EE39549C039BD373A8211F4BF5356BD8C421E49C0A8261ACEEA4DF6BFFA7A74C5563749C00D5B579B245202C0E956D276F7AE49C056266651F03301C042321B3EE39549C039BD373A8211F4BF', 454, 454, 2433, -1.79220000000000002, -50.7567000000000021, 'S 01 47 31', 'O 50 45 23', 164, 102);
INSERT INTO bdc.mux_grid VALUES ('164/103', '0106000020E61000000100000001030000000100000005000000B06F8926F8AE49C0D4FB01ADEE3301C0F0254333583749C0D4A42930215202C0FB4A282A715049C0A8F73AA7437D09C0BA946E1D11C849C0A94E1324115F08C0B06F8926F8AE49C0D4FB01ADEE3301C0', 455, 455, 2434, -2.68829999999999991, -50.9527000000000001, 'S 02 41 17', 'O 50 57 09', 164, 103);
INSERT INTO bdc.mux_grid VALUES ('164/104', '0106000020E6100000010000000103000000010000000500000064FDAD2A12C849C0DF61E99F0E5F08C0FF87734A735049C017B407913E7D09C089BB751E936949C074F04658275410C0EF30B0FE31E149C0B18E6FBF1E8A0FC064FDAD2A12C849C0DF61E99F0E5F08C0', 456, 456, 2436, -3.58429999999999982, -51.1488999999999976, 'S 03 35 03', 'O 51 08 56', 164, 104);
INSERT INTO bdc.mux_grid VALUES ('164/105', '0106000020E610000001000000010300000001000000050000009D1DF86933E149C0CF264D5A1B8A0FC04C3541F2956949C00EE973F6235410C04ABEAFC5BE8249C033BDD50CA0E913C09AA6663D5CFA49C08E6788C3895A13C09D1DF86933E149C0CF264D5A1B8A0FC0', 457, 457, 2437, -4.48029999999999973, -51.3453999999999979, 'S 04 28 49', 'O 51 20 43', 164, 105);
INSERT INTO bdc.mux_grid VALUES ('164/106', '0106000020E61000000100000001030000000100000005000000448064075EFA49C0EE85AB9F875A13C047A0554EC28249C0FA36ABD29BE913C0BA19EF47F69B49C0A1E66221097F17C0B6F9FD0092134AC0953563EEF4EF16C0448064075EFA49C0EE85AB9F875A13C0', 458, 458, 2438, -5.37619999999999987, -51.5422000000000011, 'S 05 22 34', 'O 51 32 32', 164, 106);
INSERT INTO bdc.mux_grid VALUES ('164/107', '0106000020E61000000100000001030000000100000005000000BF108D2A94134AC0BA4C3458F2EF16C0AB722187FA9B49C02AA6D90C047F17C0257F27D33BB549C0BB5CB3C45F141BC0381D9376D52C4AC04B030E104E851AC0BF108D2A94134AC0BA4C3458F2EF16C0', 459, 459, 2439, -6.27210000000000001, -51.7394000000000034, 'S 06 16 19', 'O 51 44 21', 164, 107);
INSERT INTO bdc.mux_grid VALUES ('164/108', '0106000020E61000000100000001030000000100000005000000638CBD00D82C4AC0CAC04E064B851AC045FFF1CA40B549C081EE58D359141BC0C5B8429C91CE49C09B28F423A1A91EC0E2450ED228464AC0E4FAE956921A1EC0638CBD00D82C4AC0CAC04E064B851AC0', 460, 460, 2440, -7.16790000000000038, -51.9371000000000009, 'S 07 10 04', 'O 51 56 13', 164, 108);
INSERT INTO bdc.mux_grid VALUES ('164/109', '0106000020E610000001000000010300000001000000050000005A070EBE2B464AC00FC822D88E1A1EC007CE0C4F97CE49C0D15AE8529AA91EC0472043E0F9E749C038B23835651F21C09A59444F8E5F4AC0D6E8D577DFD720C05A070EBE2B464AC00FC822D88E1A1EC0', 461, 461, 2443, -8.06359999999999921, -52.1353000000000009, 'S 08 03 49', 'O 52 08 06', 164, 109);
INSERT INTO bdc.mux_grid VALUES ('164/110', '0106000020E61000000100000001030000000100000005000000DF8E849E915F4AC09F25157DDDD720C0E775D25000E849C0F2A4315B611F21C0B29D6EE576014AC04A8DA360ECE922C0AAB6203308794AC0F70D878268A222C0DF8E849E915F4AC09F25157DDDD720C0', 462, 462, 2444, -8.95919999999999916, -52.3340000000000032, 'S 08 57 33', 'O 52 20 02', 164, 110);
INSERT INTO bdc.mux_grid VALUES ('164/111', '0106000020E61000000100000001030000000100000005000000E2263FE70B794AC066A4714B66A222C06202EA167E014AC079C93813E8E922C0A67A83FC0A1B4AC0788D85A764B424C0279FD8CC98924AC06768BEDFE26C24C0E2263FE70B794AC066A4714B66A222C0', 463, 463, 2445, -9.85479999999999912, -52.5334999999999965, 'S 09 51 17', 'O 52 32 00', 164, 111);
INSERT INTO bdc.mux_grid VALUES ('164/112', '0106000020E61000000100000001030000000100000005000000DC6DA7E79C924AC0928A3D6BE06C24C0333276F2121B4AC0246D98E45FB424C09369F881B8344AC04473B79BCC7E26C03AA5297742AC4AC0B2905C224D3726C0DC6DA7E79C924AC0928A3D6BE06C24C0', 464, 464, 2447, -10.7501999999999995, -52.7336000000000027, 'S 10 45 00', 'O 52 44 01', 164, 112);
INSERT INTO bdc.mux_grid VALUES ('164/113', '0106000020E610000001000000010300000001000000050000002145B1FA46AC4AC0F9F4386F4A3726C0F1F05540C1344AC018FAEA60C77E26C0C03449DF814E4AC0154D6CCD224928C0EF88A49907C64AC0F647BADBA50128C02145B1FA46AC4AC0F9F4386F4A3726C0', 465, 465, 2448, -11.6454000000000004, -52.9346000000000032, 'S 11 38 43', 'O 52 56 04', 164, 113);
INSERT INTO bdc.mux_grid VALUES ('164/114', '0106000020E61000000100000001030000000100000005000000E1EC25880CC64AC08AD99AE8A20128C0507E716A8B4E4AC0D99F22181D4928C096A0518C69684AC090F4F8CA65132AC0260F06AAEADF4AC0412E719BEBCB29C0E1EC25880CC64AC08AD99AE8A20128C0', 466, 466, 2449, -12.5404999999999998, -53.1364999999999981, 'S 12 32 25', 'O 53 08 11', 164, 114);
INSERT INTO bdc.mux_grid VALUES ('164/115', '0106000020E61000000100000001030000000100000005000000C01FFD05F0DF4AC08594D966E8CB29C033D115E973684AC0948350985F132AC05F26B81072824AC0AEF2952094DD2BC0ED749F2DEEF94AC09F031FEF1C962BC0C01FFD05F0DF4AC08594D966E8CB29C0', 467, 467, 2450, -13.4354999999999993, -53.3393000000000015, 'S 13 26 07', 'O 53 20 21', 164, 115);
INSERT INTO bdc.mux_grid VALUES ('164/116', '0106000020E610000001000000010300000001000000050000007ECCC5F9F3F94AC083FF6D7719962BC071DB5F447D824AC05252666D8DDD2BC0474C6A059E9C4AC01E481B58ACA72DC0553DD0BA14144BC050F5226238602DC07ECCC5F9F3F94AC083FF6D7719962BC0', 468, 468, 2451, -14.3302999999999994, -53.5431999999999988, 'S 14 19 49', 'O 53 32 35', 164, 116);
INSERT INTO bdc.mux_grid VALUES ('164/117', '0106000020E61000000100000001030000000100000005000000533220FA1A144BC0BA8F90A534602DC09A74B915AA9C4AC086B1F120A5A72DC0C97E2C16F0B64AC02D63B5F8AC712FC0823C93FA602E4BC06441547D3C2A2FC0533220FA1A144BC0BA8F90A534602DC0', 469, 469, 2453, -15.2249999999999996, -53.7481000000000009, 'S 15 13 29', 'O 53 44 53', 164, 117);
INSERT INTO bdc.mux_grid VALUES ('164/118', '0106000020E610000001000000010300000001000000050000000A3D4BB0672E4BC016C9EF79382A2FC037D16909FDB64AC090D6D039A5712FC068783F036BD14AC0BC534943CA9D30C03CE420AAD5484BC0FECC58E3137A30C00A3D4BB0672E4BC016C9EF79382A2FC0', 470, 470, 2455, -16.1193999999999988, -53.9543000000000035, 'S 16 07 09', 'O 53 57 15', 164, 118);
INSERT INTO bdc.mux_grid VALUES ('164/119', '0106000020E61000000100000001030000000100000005000000312DC7D9DC484BC062B52FBD117A30C0FC953BE078D14AC0FBD3EF1DC69D30C0B06E1DA311EC4AC0976044C1B08231C0E705A99C75634BC0FD418460FC5E31C0312DC7D9DC484BC062B52FBD117A30C0', 471, 471, 2456, -17.0137, -54.1617999999999995, 'S 17 00 49', 'O 54 09 42', 164, 119);
INSERT INTO bdc.mux_grid VALUES ('164/120', '0106000020E61000000100000001030000000100000005000000C7B70F4A7D634BC0D6CABF14FA5E31C067BC3A7120EC4AC05551CE53AC8231C0256951E4E6064BC03C7FD834896732C0856426BD437E4BC0BDF8C9F5D64332C0C7B70F4A7D634BC0D6CABF14FA5E31C0', 472, 472, 2458, -17.9076999999999984, -54.3706000000000031, 'S 17 54 27', 'O 54 22 14', 164, 120);
INSERT INTO bdc.mux_grid VALUES ('164/121', '0106000020E610000001000000010300000001000000050000009C0370EC4B7E4BC06D932D83D44332C026B18CABF6064BC0215EE27C846732C0705E6BCFED214BC01F6C7DDA524C33C0E7B04E1043994BC06BA1C8E0A22833C09C0370EC4B7E4BC06D932D83D44332C0', 473, 473, 2459, -18.8016000000000005, -54.5808999999999997, 'S 18 48 05', 'O 54 34 51', 164, 121);
INSERT INTO bdc.mux_grid VALUES ('164/122', '0106000020E610000001000000010300000001000000050000002D17F3C54B994BC0353AFE45A02833C03F4C6598FE214BC05BB472D54D4C33C0B2F11389293D4BC0ECDE59EC0C3134C0A0BCA1B676B44BC0C664E55C5F0D34C02D17F3C54B994BC0353AFE45A02833C0', 474, 474, 2460, -19.6951000000000001, -54.7927000000000035, 'S 19 41 42', 'O 54 47 33', 164, 122);
INSERT INTO bdc.mux_grid VALUES ('164/123', '0106000020E61000000100000001030000000100000005000000AC8573F77FB44BC0C4C37B985C0D34C0EE781B5D3B3D4BC0F1EC7197073134C06FE642549D584BC06A8E01A2B61535C02DF39AEEE1CF4BC03C650BA30BF234C0AC8573F77FB44BC0C4C37B985C0D34C0', 475, 475, 2461, -20.5884999999999998, -55.0061999999999998, 'S 20 35 18', 'O 55 00 22', 164, 123);
INSERT INTO bdc.mux_grid VALUES ('164/124', '0106000020E610000001000000010300000001000000050000005B72CDBFEBCF4BC0EE6574B308F234C0FAAF603DB0584BC014353CFAB01535C02CB89B944C744BC0F6CB2C304FFA35C08D7A081788EB4BC0CEFC64E9A6D635C05B72CDBFEBCF4BC0EE6574B308F234C0', 476, 476, 2463, -21.4816000000000003, -55.2214999999999989, 'S 21 28 53', 'O 55 13 17', 164, 124);
INSERT INTO bdc.mux_grid VALUES ('164/125', '0106000020E610000001000000010300000001000000050000000245367E92EB4BC07E99F3CCA3D635C036A49E9D60744BC002974E3249FA35C09604F4D03A904BC0DD1769C8D5DE36C063A58BB16C074CC0591A0E6330BB36C00245367E92EB4BC07E99F3CCA3D635C0', 477, 477, 2464, -22.3744000000000014, -55.438600000000001, 'S 22 22 27', 'O 55 26 18', 164, 125);
INSERT INTO bdc.mux_grid VALUES ('164/126', '0106000020E610000001000000010300000001000000050000009CBEBDB477074CC0DC46F4172DBB36C0F5E87E0550904BC0A82FF770CFDE36C09DEE07B66BAC4BC04711C29849C337C044C4466593234CC07C28BF3FA79F37C09CBEBDB477074CC0DC46F4172DBB36C0', 478, 478, 2466, -23.2669999999999995, -55.6576999999999984, 'S 23 16 01', 'O 55 39 27', 164, 126);
INSERT INTO bdc.mux_grid VALUES ('164/127', '0106000020E610000001000000010300000001000000050000002E7DFC0A9F234CC095770BC4A39F37C04CA5A02282AC4BC028BAFDE342C337C0CDEE6019E3C84BC07EF961CBA9A738C0AFC6BC0100404CC0EBB66FAB0A8438C02E7DFC0A9F234CC095770BC4A39F37C0', 479, 479, 2467, -24.1593000000000018, -55.8789000000000016, 'S 24 09 33', 'O 55 52 43', 164, 127);
INSERT INTO bdc.mux_grid VALUES ('164/128', '0106000020E610000001000000010300000001000000050000001663F4500C404CC059C40AFD068438C0EBDD80CBFAC84BC01EA243B5A2A738C02E1374FCA4E54BC067132986F58B39C05A98E781B65C4CC0A235F0CD596839C01663F4500C404CC059C40AFD068438C0', 480, 480, 2468, -25.0512000000000015, -56.1022000000000034, 'S 25 03 04', 'O 56 06 08', 164, 128);
INSERT INTO bdc.mux_grid VALUES ('164/129', '0106000020E610000001000000010300000001000000050000009DCC2782C35C4CC07ACF99EA556839C0BD4C9A02BEE54BC03CE95A0AEE8B39C00921FD8FB5024CC08EEF3AEA2B703AC0E9A08A0FBB794CC0CDD579CA934C3AC09DCC2782C35C4CC07ACF99EA556839C0', 481, 481, 2469, -25.9429000000000016, -56.3278999999999996, 'S 25 56 34', 'O 56 19 40', 164, 129);
INSERT INTO bdc.mux_grid VALUES ('164/130', '0106000020E61000000100000001030000000100000005000000B0FFECC8C8794CC01DDEC5AF8F4C3AC08A51C2F9CF024CC0D9E8120424703AC0B5B99C3719204CC0A8BE80134C543BC0DC67C70612974CC0EBB333BFB7303BC0B0FFECC8C8794CC01DDEC5AF8F4C3AC0', 482, 482, 2470, -26.8341999999999992, -56.5561000000000007, 'S 26 50 03', 'O 56 33 21', 164, 130);
INSERT INTO bdc.mux_grid VALUES ('164/131', '0106000020E6100000010000000103000000010000000500000020D9038220974CC0F8B2866AB3303BC01B05C91535204CC0B110FABD43543BC06629C08DD43D4CC098891F1855383CC06BFDFAF9BFB44CC0DF2BACC4C4143CC020D9038220974CC0F8B2866AB3303BC0', 483, 483, 2471, -27.7251000000000012, -56.7869000000000028, 'S 27 43 30', 'O 56 47 12', 164, 131);
INSERT INTO bdc.mux_grid VALUES ('164/132', '0106000020E61000000100000001030000000100000005000000525B7440CFB44CC08B8A3733C0143CC0E73C63F2F13D4CC0EA75D34D4C383CC07769DA67EC5B4CC0C12AE107461C3DC0E387EBB5C9D24CC0633F45EDB9F83CC0525B7440CFB44CC08B8A3733C0143CC0', 484, 484, 2472, -28.6157000000000004, -57.0204000000000022, 'S 28 36 56', 'O 57 01 13', 164, 132);
INSERT INTO bdc.mux_grid VALUES ('164/133', '0106000020E61000000100000001030000000100000005000000AA82BDD1D9D24CC0BB1F031CB5F83CC0ADF065660B5C4CC0A015FFC23C1C3DC0B194F6DA657A4CC0EBBA8EEB1D003EC0AF264E4634F14CC006C5924496DC3DC0AA82BDD1D9D24CC0BB1F031CB5F83CC0', 485, 485, 2473, -29.5060000000000002, -57.2567999999999984, 'S 29 30 21', 'O 57 15 24', 164, 133);
INSERT INTO bdc.mux_grid VALUES ('164/134', '0106000020E61000000100000001030000000100000005000000AD905C4245F14CC02C6F413091DC3DC05C615B88867A4CC03D73D32514003EC01A14AD4046994CC0C7EC3AC4DBE33EC06943AEFA04104DC0B8E8A8CE58C03EC0AD905C4245F14CC02C6F413091DC3DC0', 486, 486, 2474, -30.3958000000000013, -57.4962000000000018, 'S 30 23 44', 'O 57 29 46', 164, 134);
INSERT INTO bdc.mux_grid VALUES ('164/135', '0106000020E610000001000000010300000001000000050000002EF4B5E216104DC002BEC57353C03EC01C3C7BB368994CC03311E776D1E33EC018CB853C93B84CC056CA7A8A7EC73FC02983C06B412F4DC02577598700A43FC02EF4B5E216104DC002BEC57353C03EC0', 487, 487, 2477, -31.2852999999999994, -57.7387999999999977, 'S 31 17 06', 'O 57 44 19', 164, 135);
INSERT INTO bdc.mux_grid VALUES ('164/136', '0106000020E61000000100000001030000000100000005000000A5F9694C542F4DC0925F1BE2FAA33FC0601B108DB7B84CC0672F48AE73C73FC081CAD2C152D84CC04278C596825540C0C6A82C81EF4E4DC05A10AF30C64340C0A5F9694C542F4DC0925F1BE2FAA33FC0', 488, 488, 2478, -32.1743000000000023, -57.9849000000000032, 'S 32 10 27', 'O 57 59 05', 164, 136);
INSERT INTO bdc.mux_grid VALUES ('164/137', '0106000020E6100000010000000103000000010000000500000058A32068034F4DC026B1D736C34340C070EA550A79D84CC0247650DD7C5540C08663101A8BF84CC06AA12F4937C740C06E1CDB77156F4DC06CDCB6A27DB540C058A32068034F4DC026B1D736C34340C0', 489, 489, 2479, -33.0628999999999991, -58.234499999999997, 'S 33 03 46', 'O 58 14 04', 164, 137);
INSERT INTO bdc.mux_grid VALUES ('164/138', '0106000020E61000000100000001030000000100000005000000A465D9732A6F4DC01093727F7AB540C0BB1ADE76B3F84CC0F2DD224031C740C06A0AD9EB42194DC0DE694DC9DC3841C04F55D4E8B98F4DC0FA1E9D08262741C0A465D9732A6F4DC01093727F7AB540C0', 490, 490, 2481, -33.9510000000000005, -58.4879000000000033, 'S 33 57 03', 'O 58 29 16', 164, 138);
INSERT INTO bdc.mux_grid VALUES ('164/139', '0106000020E610000001000000010300000001000000050000002E02CD09D08F4DC0A6D489B9222741C08127887B6D194DC006F7156CD63841C030387D42813A4DC03AB4B67D72AA41C0DF12C2D0E3B04DC0D8912ACBBE9841C02E02CD09D08F4DC0A6D489B9222741C0', 491, 491, 2482, -34.8387000000000029, -58.7453000000000003, 'S 34 50 19', 'O 58 44 43', 164, 139);
INSERT INTO bdc.mux_grid VALUES ('164/140', '0106000020E61000000100000001030000000100000005000000CC86F127FBB04DC04E7FB44DBB9841C0E5A31E26AE3A4DC0FCD262C76BAA41C0297951964D5C4DC0CAD829C6F71B42C0105C24989AD24DC01A857B4C470A42C0CC86F127FBB04DC04E7FB44DBB9841C0', 492, 492, 2483, -35.7257999999999996, -59.0069000000000017, 'S 35 43 33', 'O 59 00 24', 164, 140);
INSERT INTO bdc.mux_grid VALUES ('164/141', '0106000020E6100000010000000103000000010000000500000083603238B3D24DC0728CD89D430A42C0B81CABF17C5C4DC0802A60B1F01B42C06628C7D5AF7E4DC0BC78DBFA6B8D42C02F6C4E1CE6F44DC0AEDA53E7BE7B42C083603238B3D24DC0728CD89D430A42C0', 493, 493, 2485, -36.6124999999999972, -59.2728999999999999, 'S 36 36 45', 'O 59 16 22', 164, 141);
INSERT INTO bdc.mux_grid VALUES ('164/142', '0106000020E6100000010000000103000000010000000500000056CB701900F54DC0B65A7E04BB7B42C0E85695CFE17E4DC02A37D181648D42C05FEC666FB0A14DC03F39B46BCEFE42C0CE6042B9CE174EC0CA5C61EE24ED42C056CB701900F54DC0B65A7E04BB7B42C0', 494, 494, 2486, -37.4986000000000033, -59.5435999999999979, 'S 37 29 55', 'O 59 32 37', 164, 142);
INSERT INTO bdc.mux_grid VALUES ('164/143', '0106000020E610000001000000010300000001000000050000004A676329EA174EC0066F12D420ED42C0C92CA531E5A14DC044542288C6FE42C02014C75C58C54DC03E3C7A5F1E7043C09F4E85545D3B4EC0FE566AAB785E43C04A676329EA174EC0066F12D420ED42C0', 495, 495, 2487, -38.3841999999999999, -59.8192999999999984, 'S 38 23 03', 'O 59 49 09', 164, 143);
INSERT INTO bdc.mux_grid VALUES ('164/99', '0106000020E61000000100000001030000000100000005000000C55A1910AE4A49C0A906CC6FC2F1F63FC6626D1F0DD348C060BE00AD58B5F43FDE9713C51FEC48C0E33A4E30C47BD93FDD8FBFB5C06349C0FBADBD9DB536E13FC55A1910AE4A49C0A906CC6FC2F1F63F', 496, 496, 2533, 0.896100000000000008, -50.1691000000000003, 'N 00 53 45', 'O 50 10 08', 164, 99);
INSERT INTO bdc.mux_grid VALUES ('165/100', '0106000020E6100000010000000103000000010000000500000041F0C6414ADF49C0D30D24BEB136E13FA864D411A96749C01EAD07B6B77BD93F1182B322BA8049C04A59525307DEDFBFAB0DA6525BF849C0C2EA118D5BECD6BF41F0C6414ADF49C0D30D24BEB136E13F', 497, 497, 2534, 0, -51.3301000000000016, 'N 00 00 00', 'O 51 19 48', 165, 100);
INSERT INTO bdc.mux_grid VALUES ('165/101', '0106000020E610000001000000010300000001000000050000007FB51A485BF849C0CB75E2565CECD6BF3CDA3E2DBA8049C02ACE818906DEDFBF677262C4CB9949C0CFFDAB51EE4DF6BFA94D3EDF6C114AC0BB2704C58311F4BF7FB51A485BF849C0CB75E2565CECD6BF', 498, 498, 2536, -0.896100000000000008, -51.5259, 'S 00 53 45', 'O 51 31 33', 165, 101);
INSERT INTO bdc.mux_grid VALUES ('165/102', '0106000020E61000000100000001030000000100000005000000E099C0316D114AC001BD373A8211F4BFF5BD6280CC9949C05B261ACEEA4DF6BF9CE219B9E0B249C0F55A579B245202C087BE776A812A4AC048266651F03301C0E099C0316D114AC001BD373A8211F4BF', 499, 499, 2537, -1.79220000000000002, -51.7218000000000018, 'S 01 47 31', 'O 51 43 18', 165, 102);
INSERT INTO bdc.mux_grid VALUES ('165/103', '0106000020E6100000010000000103000000010000000500000053D72E1A822A4AC0BEFB01ADEE3301C0938DE826E2B249C0BEA42930215202C09DB2CD1DFBCB49C088F73AA7437D09C05EFC13119B434AC0884E1324115F08C053D72E1A822A4AC0BEFB01ADEE3301C0', 500, 500, 2539, -2.68829999999999991, -51.9177999999999997, 'S 02 41 17', 'O 51 55 04', 165, 103);
INSERT INTO bdc.mux_grid VALUES ('165/104', '0106000020E61000000100000001030000000100000005000000FD64531E9C434AC0D661E99F0E5F08C0A9EF183EFDCB49C0E7B307913E7D09C034231B121DE549C099F04658275410C0889855F2BB5C4AC01E8F6FBF1E8A0FC0FD64531E9C434AC0D661E99F0E5F08C0', 501, 501, 2540, -3.58429999999999982, -52.1141000000000005, 'S 03 35 03', 'O 52 06 50', 165, 104);
INSERT INTO bdc.mux_grid VALUES ('165/105', '0106000020E6100000010000000103000000010000000500000044859D5DBD5C4AC023274D5A1B8A0FC0EA9CE6E51FE549C040E973F6235410C0E52555B948FE49C015BDD50CA0E913C03E0E0C31E6754AC0666788C3895A13C044859D5DBD5C4AC023274D5A1B8A0FC0', 502, 502, 2541, -4.48029999999999973, -52.3106000000000009, 'S 04 28 49', 'O 52 18 38', 165, 105);
INSERT INTO bdc.mux_grid VALUES ('165/106', '0106000020E61000000100000001030000000100000005000000D8E709FBE7754AC0DA85AB9F875A13C0E507FB414CFE49C0DB36ABD29BE913C05A81943B80174AC0FCE66221097F17C04D61A3F41B8F4AC0FB3563EEF4EF16C0D8E709FBE7754AC0DA85AB9F875A13C0', 503, 503, 2542, -5.37619999999999987, -52.507399999999997, 'S 05 22 34', 'O 52 30 26', 165, 106);
INSERT INTO bdc.mux_grid VALUES ('165/107', '0106000020E610000001000000010300000001000000050000005878321E1E8F4AC01E4D3458F2EF16C067DAC67A84174AC066A6D90C047F17C0DEE6CCC6C5304AC0B15CB3C45F141BC0CF84386A5FA84AC06B030E104E851AC05878321E1E8F4AC01E4D3458F2EF16C0', 504, 504, 2543, -6.27210000000000001, -52.7045999999999992, 'S 06 16 19', 'O 52 42 16', 165, 107);
INSERT INTO bdc.mux_grid VALUES ('165/108', '0106000020E6100000010000000103000000010000000500000003F462F461A84AC0E1C04E064B851AC0E56697BECA304AC096EE58D359141BC06320E88F1B4A4AC06C28F423A1A91EC080ADB3C5B2C14AC0B7FAE956921A1EC003F462F461A84AC0E1C04E064B851AC0', 505, 505, 2545, -7.16790000000000038, -52.9022000000000006, 'S 07 10 04', 'O 52 54 08', 165, 108);
INSERT INTO bdc.mux_grid VALUES ('165/109', '0106000020E61000000100000001030000000100000005000000FC6EB3B1B5C14AC0D9C722D88E1A1EC09735B242214A4AC0B15AE8529AA91EC0D887E8D383634AC050B23835651F21C03DC1E94218DB4AC0E4E8D577DFD720C0FC6EB3B1B5C14AC0D9C722D88E1A1EC0', 506, 506, 2547, -8.06359999999999921, -53.1004000000000005, 'S 08 03 49', 'O 53 06 01', 165, 109);
INSERT INTO bdc.mux_grid VALUES ('165/110', '0106000020E6100000010000000103000000010000000500000083F629921BDB4AC0AE25157DDDD720C08BDD77448A634AC001A5315B611F21C0570514D9007D4AC0788DA360ECE922C04F1EC62692F44AC0230E878268A222C083F629921BDB4AC0AE25157DDDD720C0', 507, 507, 2548, -8.95919999999999916, -53.299199999999999, 'S 08 57 33', 'O 53 17 57', 165, 110);
INSERT INTO bdc.mux_grid VALUES ('165/111', '0106000020E61000000100000001030000000100000005000000848EE4DA95F44AC097A4714B66A222C0136A8F0A087D4AC09CC93813E8E922C05BE228F094964AC0BB8D85A764B424C0CB067EC0220E4BC0B468BEDFE26C24C0848EE4DA95F44AC097A4714B66A222C0', 508, 508, 2549, -9.85479999999999912, -53.4986000000000033, 'S 09 51 17', 'O 53 29 55', 165, 111);
INSERT INTO bdc.mux_grid VALUES ('165/112', '0106000020E6100000010000000103000000010000000500000084D54CDB260E4BC0DB8A3D6BE06C24C0DB991BE69C964AC06F6D98E45FB424C035D19D7542B04AC02B73B79BCC7E26C0DC0CCF6ACC274BC097905C224D3726C084D54CDB260E4BC0DB8A3D6BE06C24C0', 509, 509, 2550, -10.7501999999999995, -53.6987999999999985, 'S 10 45 00', 'O 53 41 55', 165, 112);
INSERT INTO bdc.mux_grid VALUES ('165/113', '0106000020E61000000100000001030000000100000005000000C0AC56EED0274BC0E2F4386F4A3726C09258FB334BB04AC004FAEA60C77E26C06B9CEED20BCA4AC09E4D6CCD224928C099F0498D91414BC07C48BADBA50128C0C0AC56EED0274BC0E2F4386F4A3726C0', 510, 510, 2551, -11.6454000000000004, -53.899799999999999, 'S 11 38 43', 'O 53 53 59', 165, 113);
INSERT INTO bdc.mux_grid VALUES ('165/114', '0106000020E610000001000000010300000001000000050000009B54CB7B96414BC005DA9AE8A20128C0E9E5165E15CA4AC06BA022181D4928C02608F77FF3E34AC0C0F4F8CA65132AC0D976AB9D745B4BC05A2E719BEBCB29C09B54CB7B96414BC005DA9AE8A20128C0', 511, 511, 2552, -12.5404999999999998, -54.1015999999999977, 'S 12 32 25', 'O 54 06 05', 165, 114);
INSERT INTO bdc.mux_grid VALUES ('165/115', '0106000020E610000001000000010300000001000000050000006987A2F9795B4BC0A494D966E8CB29C0DB38BBDCFDE34AC0B48350985F132AC00A8E5D04FCFD4AC0EEF2952094DD2BC097DC442178754BC0DE031FEF1C962BC06987A2F9795B4BC0A494D966E8CB29C0', 512, 512, 2553, -13.4354999999999993, -54.3044999999999973, 'S 13 26 07', 'O 54 18 16', 165, 115);
INSERT INTO bdc.mux_grid VALUES ('165/116', '0106000020E6100000010000000103000000010000000500000046346BED7D754BC0B0FF6D7719962BC01643053807FE4AC09352666D8DDD2BC0E7B30FF927184BC0FD471B58ACA72DC017A575AE9E8F4BC01AF5226238602DC046346BED7D754BC0B0FF6D7719962BC0', 513, 513, 2555, -14.3302999999999994, -54.5082999999999984, 'S 14 19 49', 'O 54 30 29', 165, 116);
INSERT INTO bdc.mux_grid VALUES ('165/117', '0106000020E61000000100000001030000000100000005000000EA99C5EDA48F4BC09D8F90A534602DC030DC5E0934184BC069B1F120A5A72DC061E6D1097A324BC02F63B5F8AC712FC019A438EEEAA94BC06441547D3C2A2FC0EA99C5EDA48F4BC09D8F90A534602DC0', 514, 514, 2556, -15.2249999999999996, -54.7132999999999967, 'S 15 13 29', 'O 54 42 47', 165, 117);
INSERT INTO bdc.mux_grid VALUES ('165/118', '0106000020E61000000100000001030000000100000005000000CBA4F0A3F1A94BC000C9EF79382A2FC0B3380FFD86324BC0A5D6D039A5712FC0ECDFE4F6F44C4BC001544943CA9D30C0034CC69D5FC44BC02FCD58E3137A30C0CBA4F0A3F1A94BC000C9EF79382A2FC0', 515, 515, 2558, -16.1193999999999988, -54.9194999999999993, 'S 16 07 09', 'O 54 55 10', 165, 118);
INSERT INTO bdc.mux_grid VALUES ('165/119', '0106000020E61000000100000001030000000100000005000000E9946CCD66C44BC097B52FBD117A30C0B3FDE0D3024D4BC030D4EF1DC69D30C063D6C2969B674BC09A6044C1B08231C09A6D4E90FFDE4BC002428460FC5E31C0E9946CCD66C44BC097B52FBD117A30C0', 516, 516, 2560, -17.0137, -55.1268999999999991, 'S 17 00 49', 'O 55 07 36', 165, 119);
INSERT INTO bdc.mux_grid VALUES ('165/120', '0106000020E610000001000000010300000001000000050000004C1FB53D07DF4BC0E8CABF14FA5E31C00E24E064AA674BC05B51CE53AC8231C0CFD0F6D770824BC0517FD834896732C00CCCCBB0CDF94BC0DFF8C9F5D64332C04C1FB53D07DF4BC0E8CABF14FA5E31C0', 517, 517, 2561, -17.9076999999999984, -55.3357000000000028, 'S 17 54 27', 'O 55 20 08', 165, 120);
INSERT INTO bdc.mux_grid VALUES ('165/121', '0106000020E61000000100000001030000000100000005000000536B15E0D5F94BC07D932D83D44332C09618329F80824BC0455EE27C846732C0E5C510C3779D4BC0536C7DDA524C33C0A118F403CD144CC08BA1C8E0A22833C0536B15E0D5F94BC07D932D83D44332C0', 518, 518, 2562, -18.8016000000000005, -55.5459999999999994, 'S 18 48 05', 'O 55 32 45', 165, 121);
INSERT INTO bdc.mux_grid VALUES ('165/122', '0106000020E61000000100000001030000000100000005000000D67E98B9D5144CC05C3AFE45A02833C0A4B30A8C889D4BC095B472D54D4C33C01859B97CB3B84BC036DF59EC0C3134C04B2447AA00304CC0FD64E55C5F0D34C0D67E98B9D5144CC05C3AFE45A02833C0', 519, 519, 2563, -19.6951000000000001, -55.7578999999999994, 'S 19 41 42', 'O 55 45 28', 165, 122);
INSERT INTO bdc.mux_grid VALUES ('165/123', '0106000020E610000001000000010300000001000000050000003FED18EB09304CC001C47B985C0D34C0C6E0C050C5B84BC018ED7197073134C0394EE84727D44BC0218E01A2B61535C0B25A40E26B4B4CC00A650BA30BF234C03FED18EB09304CC001C47B985C0D34C0', 520, 520, 2564, -20.5884999999999998, -55.9714000000000027, 'S 20 35 18', 'O 55 58 16', 165, 123);
INSERT INTO bdc.mux_grid VALUES ('165/124', '0106000020E61000000100000001030000000100000005000000E3D972B3754B4CC0BA6574B308F234C0821706313AD44BC0E0343CFAB01535C0A51F4188D6EF4BC04ECB2C304FFA35C006E2AD0A12674CC029FC64E9A6D635C0E3D972B3754B4CC0BA6574B308F234C0', 521, 521, 2565, -21.4816000000000003, -56.1865999999999985, 'S 21 28 53', 'O 56 11 11', 165, 124);
INSERT INTO bdc.mux_grid VALUES ('165/125', '0106000020E6100000010000000103000000010000000500000062ACDB711C674CC0E298F3CCA3D635C0950B4491EAEF4BC063964E3249FA35C0086C99C4C40B4CC0CC1769C8D5DE36C0D50C31A5F6824CC04C1A0E6330BB36C062ACDB711C674CC0E298F3CCA3D635C0', 522, 522, 2566, -22.3744000000000014, -56.4037000000000006, 'S 22 22 27', 'O 56 24 13', 165, 125);
INSERT INTO bdc.mux_grid VALUES ('165/126', '0106000020E61000000100000001030000000100000005000000252663A801834CC0C846F4172DBB36C07C5024F9D90B4CC0922FF770CFDE36C03656ADA9F5274CC0C011C29849C337C0DF2BEC581D9F4CC0F628BF3FA79F37C0252663A801834CC0C846F4172DBB36C0', 523, 523, 2568, -23.2669999999999995, -56.622799999999998, 'S 23 16 01', 'O 56 37 22', 165, 126);
INSERT INTO bdc.mux_grid VALUES ('165/127', '0106000020E61000000100000001030000000100000005000000CEE4A1FE289F4CC010780BC4A39F37C0310D46160C284CC08CBAFDE342C337C0A456060D6D444CC070F961CBA9A738C0422E62F589BB4CC0F3B66FAB0A8438C0CEE4A1FE289F4CC010780BC4A39F37C0', 524, 524, 2570, -24.1593000000000018, -56.8440000000000012, 'S 24 09 33', 'O 56 50 38', 165, 127);
INSERT INTO bdc.mux_grid VALUES ('165/128', '0106000020E6100000010000000103000000010000000500000093CA994496BB4CC067C40AFD068438C0684526BF84444CC02BA243B5A2A738C09E7A19F02E614CC003132986F58B39C0C8FF8C7540D84CC03F35F0CD596839C093CA994496BB4CC067C40AFD068438C0', 525, 525, 2571, -25.0512000000000015, -57.0673999999999992, 'S 25 03 04', 'O 57 04 02', 165, 128);
INSERT INTO bdc.mux_grid VALUES ('165/129', '0106000020E610000001000000010300000001000000050000005534CD754DD84CC001CF99EA556839C073B43FF647614CC0C1E85A0AEE8B39C0D188A2833F7E4CC0A2EF3AEA2B703AC0B208300345F54CC0E2D579CA934C3AC05534CD754DD84CC001CF99EA556839C0', 526, 526, 2572, -25.9429000000000016, -57.2931000000000026, 'S 25 56 34', 'O 57 17 35', 165, 129);
INSERT INTO bdc.mux_grid VALUES ('165/130', '0106000020E61000000100000001030000000100000005000000486792BC52F54CC043DEC5AF8F4C3AC020B967ED597E4CC0FFE8120424703AC04E21422BA39B4CC0DCBE80134C543BC074CF6CFA9B124DC020B433BFB7303BC0486792BC52F54CC043DEC5AF8F4C3AC0', 527, 527, 2573, -26.8341999999999992, -57.5212999999999965, 'S 26 50 03', 'O 57 31 16', 165, 130);
INSERT INTO bdc.mux_grid VALUES ('165/131', '0106000020E61000000100000001030000000100000005000000A340A975AA124DC035B3866AB3303BC0E36C6E09BF9B4CC0D710FABD43543BC0309165815EB94CC0CE891F1855383CC0EE64A0ED49304DC02B2CACC4C4143CC0A340A975AA124DC035B3866AB3303BC0', 528, 528, 2575, -27.7251000000000012, -57.7520000000000024, 'S 27 43 30', 'O 57 45 07', 165, 131);
INSERT INTO bdc.mux_grid VALUES ('165/132', '0106000020E610000001000000010300000001000000050000001FC3193459304DC0C18A3733C0143CC06FA408E67BB94CC03276D34D4C383CC002D17F5B76D74CC0172BE107461C3DC0B2EF90A9534E4DC0A53F45EDB9F83CC01FC3193459304DC0C18A3733C0143CC0', 529, 529, 2576, -28.6157000000000004, -57.9855000000000018, 'S 28 36 56', 'O 57 59 07', 165, 132);
INSERT INTO bdc.mux_grid VALUES ('165/133', '0106000020E6100000010000000103000000010000000500000041EA62C5634E4DC01120031CB5F83CC089580B5A95D74CC0E115FFC23C1C3DC07DFC9BCEEFF54CC0BBBA8EEB1D003EC0368EF339BE6C4DC0EBC4924496DC3DC041EA62C5634E4DC01120031CB5F83CC0', 530, 530, 2577, -29.5060000000000002, -58.221899999999998, 'S 29 30 21', 'O 58 13 18', 165, 133);
INSERT INTO bdc.mux_grid VALUES ('165/134', '0106000020E610000001000000010300000001000000050000003BF80136CF6C4DC0106F413091DC3DC0E8C8007C10F64CC01D73D32514003EC0A97B5234D0144DC0B7EC3AC4DBE33EC0F9AA53EE8E8B4DC0A9E8A8CE58C03EC03BF80136CF6C4DC0106F413091DC3DC0', 531, 531, 2578, -30.3958000000000013, -58.4613000000000014, 'S 30 23 44', 'O 58 27 40', 165, 134);
INSERT INTO bdc.mux_grid VALUES ('165/135', '0106000020E61000000100000001030000000100000005000000F55B5BD6A08B4DC0E5BDC57353C03EC0A0A320A7F2144DC02911E776D1E33EC0AD322B301D344DC0D5CA7A8A7EC73FC005EB655FCBAA4DC09477598700A43FC0F55B5BD6A08B4DC0E5BDC57353C03EC0', 532, 532, 2580, -31.2852999999999994, -58.7040000000000006, 'S 31 17 06', 'O 58 42 14', 165, 135);
INSERT INTO bdc.mux_grid VALUES ('165/136', '0106000020E6100000010000000103000000010000000500000043610F40DEAA4DC015601BE2FAA33FC04583B58041344DC0D32F48AE73C73FC0593278B5DC534DC04C78C596825540C05810D27479CA4DC06C10AF30C64340C043610F40DEAA4DC015601BE2FAA33FC0', 533, 533, 2581, -32.1743000000000023, -58.9500000000000028, 'S 32 10 27', 'O 58 57 00', 165, 136);
INSERT INTO bdc.mux_grid VALUES ('165/137', '0106000020E61000000100000001030000000100000005000000050BC65B8DCA4DC034B1D736C34340C01D52FBFD02544DC0357650DD7C5540C023CBB50D15744DC040A12F4937C740C00B84806B9FEA4DC042DCB6A27DB540C0050BC65B8DCA4DC034B1D736C34340C0', 534, 534, 2583, -33.0628999999999991, -59.1997, 'S 33 03 46', 'O 59 11 58', 165, 137);
INSERT INTO bdc.mux_grid VALUES ('165/138', '0106000020E61000000100000001030000000100000005000000F4CC7E67B4EA4DC0F092727F7AB540C05382836A3D744DC0CADD224031C740C015727EDFCC944DC0FC694DC9DC3841C0B5BC79DC430B4EC0221F9D08262741C0F4CC7E67B4EA4DC0F092727F7AB540C0', 535, 535, 2584, -33.9510000000000005, -59.4530999999999992, 'S 33 57 03', 'O 59 27 11', 165, 138);
INSERT INTO bdc.mux_grid VALUES ('165/139', '0106000020E610000001000000010300000001000000050000000D6A72FD590B4EC0BCD489B9222741C0D48E2D6FF7944DC032F7156CD63841C0999F22360BB64DC0AAB4B67D72AA41C0D27A67C46D2C4EC034922ACBBE9841C00D6A72FD590B4EC0BCD489B9222741C0', 536, 536, 2585, -34.8387000000000029, -59.7103999999999999, 'S 34 50 19', 'O 59 42 37', 165, 139);
INSERT INTO bdc.mux_grid VALUES ('165/140', '0106000020E61000000100000001030000000100000005000000EFEE961B852C4EC0A27FB44DBB9841C0080CC41938B64DC054D362C76BAA41C029E1F689D7D74DC0A8D829C6F71B42C00FC4C98B244E4EC0F8847B4C470A42C0EFEE961B852C4EC0A27FB44DBB9841C0', 537, 537, 2586, -35.7257999999999996, -59.9720000000000013, 'S 35 43 33', 'O 59 58 19', 165, 140);
INSERT INTO bdc.mux_grid VALUES ('165/141', '0106000020E610000001000000010300000001000000050000005DC8D72B3D4E4EC0568CD89D430A42C0928450E506D84DC0642A60B1F01B42C041906CC939FA4DC0A878DBFA6B8D42C00AD4F30F70704EC09ADA53E7BE7B42C05DC8D72B3D4E4EC0568CD89D430A42C0', 538, 538, 2587, -36.6124999999999972, -60.2381000000000029, 'S 36 36 45', 'O 60 14 17', 165, 141);
INSERT INTO bdc.mux_grid VALUES ('165/142', '0106000020E61000000100000001030000000100000005000000F532160D8A704EC0AA5A7E04BB7B42C012BF3AC36BFA4DC00A37D181648D42C089540C633A1D4EC02439B46BCEFE42C06EC8E7AC58934EC0C45C61EE24ED42C0F532160D8A704EC0AA5A7E04BB7B42C0', 539, 539, 2588, -37.4986000000000033, -60.5088000000000008, 'S 37 29 55', 'O 60 30 31', 165, 142);
INSERT INTO bdc.mux_grid VALUES ('165/143', '0106000020E6100000010000000103000000010000000500000000CF081D74934EC0FC6E12D420ED42C0F7934A256F1D4EC050542288C6FE42C04F7B6C50E2404EC0503C7A5F1E7043C058B62A48E7B64EC0FE566AAB785E43C000CF081D74934EC0FC6E12D420ED42C0', 540, 540, 2589, -38.3841999999999999, -60.784399999999998, 'S 38 23 03', 'O 60 47 03', 165, 143);
INSERT INTO bdc.mux_grid VALUES ('165/97', '0106000020E61000000100000001030000000100000005000000975C7770079449C0BF6C65C72ACF0940623311FC671C49C0191AC973F9B00840BD2B8120843549C0D6641597DE850140F154E79423AD49C07DB7B1EA0FA40240975C7770079449C0BF6C65C72ACF0940', 541, 541, 2640, 2.68829999999999991, -50.7423000000000002, 'N 02 41 17', 'O 50 44 32', 165, 97);
INSERT INTO bdc.mux_grid VALUES ('165/98', '0106000020E610000001000000010300000001000000050000003BBE637222AD49C010D2A6330DA402407CC17915823549C0873FC2B3D985014063BEB66B984E49C0AC12141E5FB5F43F21BBA0C838C649C0BF37DD1DC6F1F63F3BBE637222AD49C010D2A6330DA40240', 542, 542, 2641, 1.79220000000000002, -50.9382999999999981, 'N 01 47 31', 'O 50 56 17', 165, 98);
INSERT INTO bdc.mux_grid VALUES ('165/99', '0106000020E6100000010000000103000000010000000500000064C2BE0338C649C08806CC6FC2F1F63F6ACA1213974E49C058BE00AD58B5F43F82FFB8B8A96749C0FC3A4E30C47BD93F7CF764A94ADF49C0E6ADBD9DB536E13F64C2BE0338C649C08806CC6FC2F1F63F', 543, 543, 2642, 0.896100000000000008, -51.1341999999999999, 'N 00 53 45', 'O 51 08 03', 165, 99);
INSERT INTO bdc.mux_grid VALUES ('166/100', '0106000020E61000000100000001030000000100000005000000E5576C35D45A4AC0B80D24BEB136E13F48CC790533E349C0A0AC07B6B77BD93FB1E9581644FC49C0C959525307DEDFBF4E754B46E5734AC0F7EA118D5BECD6BFE5576C35D45A4AC0B80D24BEB136E13F', 544, 544, 2644, 0, -52.2952000000000012, 'N 00 00 00', 'O 52 17 42', 166, 100);
INSERT INTO bdc.mux_grid VALUES ('166/101', '0106000020E61000000100000001030000000100000005000000231DC03BE5734AC00176E2565CECD6BFDE41E42044FC49C0A8CE818906DEDFBF07DA07B855154AC0CFFDAB51EE4DF6BF4DB5E3D2F68C4AC0A62704C58311F4BF231DC03BE5734AC00176E2565CECD6BF', 545, 545, 2646, -0.896100000000000008, -52.491100000000003, 'S 00 53 45', 'O 52 29 27', 166, 101);
INSERT INTO bdc.mux_grid VALUES ('166/102', '0106000020E6100000010000000103000000010000000500000088016625F78C4AC0E2BC373A8211F4BF9425087456154AC064261ACEEA4DF6BF3B4ABFAC6A2E4AC0FB5A579B245202C02E261D5E0BA64AC037266651F03301C088016625F78C4AC0E2BC373A8211F4BF', 546, 546, 2648, -1.79220000000000002, -52.6869999999999976, 'S 01 47 31', 'O 52 41 13', 166, 102);
INSERT INTO bdc.mux_grid VALUES ('166/103', '0106000020E61000000100000001030000000100000005000000F73ED40D0CA64AC0B3FB01ADEE3301C036F58D1A6C2E4AC0B5A42930215202C0411A731185474AC0C2F73AA7437D09C00164B90425BF4AC0C04E1324115F08C0F73ED40D0CA64AC0B3FB01ADEE3301C0', 547, 547, 2649, -2.68829999999999991, -52.8830000000000027, 'S 02 41 17', 'O 52 52 58', 166, 103);
INSERT INTO bdc.mux_grid VALUES ('166/104', '0106000020E61000000100000001030000000100000005000000A8CCF81126BF4AC0FC61E99F0E5F08C04357BE3187474AC036B407913E7D09C0CD8AC005A7604AC080F04658275410C03300FBE545D84AC0C68E6FBF1E8A0FC0A8CCF81126BF4AC0FC61E99F0E5F08C0', 548, 548, 2650, -3.58429999999999982, -53.0792000000000002, 'S 03 35 03', 'O 53 04 45', 166, 104);
INSERT INTO bdc.mux_grid VALUES ('166/105', '0106000020E61000000100000001030000000100000005000000E8EC425147D84AC0D8264D5A1B8A0FC08F048CD9A9604AC01BE973F6235410C08D8DFAACD2794AC070BDD50CA0E913C0E675B12470F14AC0C16788C3895A13C0E8EC425147D84AC0D8264D5A1B8A0FC0', 549, 549, 2651, -4.48029999999999973, -53.2757000000000005, 'S 04 28 49', 'O 53 16 32', 166, 105);
INSERT INTO bdc.mux_grid VALUES ('166/106', '0106000020E61000000100000001030000000100000005000000934FAFEE71F14AC01E86AB9F875A13C07C6FA035D6794AC04937ABD29BE913C0EFE8392F0A934AC0EAE66221097F17C004C948E8A50A4BC0C03563EEF4EF16C0934FAFEE71F14AC01E86AB9F875A13C0', 550, 550, 2652, -5.37619999999999987, -53.4724999999999966, 'S 05 22 34', 'O 53 28 21', 166, 106);
INSERT INTO bdc.mux_grid VALUES ('166/107', '0106000020E61000000100000001030000000100000005000000EFDFD711A80A4BC00A4D3458F2EF16C0FE416C6E0E934AC04FA6D90C047F17C0754E72BA4FAC4AC09C5CB3C45F141BC067ECDD5DE9234BC056030E104E851AC0EFDFD711A80A4BC00A4D3458F2EF16C0', 551, 551, 2654, -6.27210000000000001, -53.6696999999999989, 'S 06 16 19', 'O 53 40 10', 166, 107);
INSERT INTO bdc.mux_grid VALUES ('166/108', '0106000020E61000000100000001030000000100000005000000B25B08E8EB234BC0AEC04E064B851AC083CE3CB254AC4AC079EE58D359141BC002888D83A5C54AC04E28F423A1A91EC0301559B93C3D4BC083FAE956921A1EC0B25B08E8EB234BC0AEC04E064B851AC0', 552, 552, 2655, -7.16790000000000038, -53.8674000000000035, 'S 07 10 04', 'O 53 52 02', 166, 108);
INSERT INTO bdc.mux_grid VALUES ('166/109', '0106000020E610000001000000010300000001000000050000009ED658A53F3D4BC0B7C722D88E1A1EC03B9D5736ABC54AC08F5AE8529AA91EC07CEF8DC70DDF4AC03EB23835651F21C0DF288F36A2564BC0D2E8D577DFD720C09ED658A53F3D4BC0B7C722D88E1A1EC0', 553, 553, 2657, -8.06359999999999921, -54.0656000000000034, 'S 08 03 49', 'O 54 03 56', 166, 109);
INSERT INTO bdc.mux_grid VALUES ('166/110', '0106000020E61000000100000001030000000100000005000000275ECF85A5564BC09B25157DDDD720C02D451D3814DF4AC0EEA4315B611F21C0F56CB9CC8AF84AC0258DA360ECE922C0EE856B1A1C704BC0D10D878268A222C0275ECF85A5564BC09B25157DDDD720C0', 554, 554, 2658, -8.95919999999999916, -54.2642999999999986, 'S 08 57 33', 'O 54 15 51', 166, 110);
INSERT INTO bdc.mux_grid VALUES ('166/111', '0106000020E610000001000000010300000001000000050000001EF689CE1F704BC045A4714B66A222C0AED134FE91F84AC04DC93813E8E922C0FD49CEE31E124BC0EB8D85A764B424C06D6E23B4AC894BC0E368BEDFE26C24C01EF689CE1F704BC045A4714B66A222C0', 555, 555, 2660, -9.85479999999999912, -54.4637999999999991, 'S 09 51 17', 'O 54 27 49', 166, 111);
INSERT INTO bdc.mux_grid VALUES ('166/112', '0106000020E610000001000000010300000001000000050000002B3DF2CEB0894BC0088B3D6BE06C24C08201C1D926124BC09C6D98E45FB424C0DA384369CC2B4BC05773B79BCC7E26C08274745E56A34BC0C4905C224D3726C02B3DF2CEB0894BC0088B3D6BE06C24C0', 556, 556, 2661, -10.7501999999999995, -54.6638999999999982, 'S 10 45 00', 'O 54 39 50', 166, 112);
INSERT INTO bdc.mux_grid VALUES ('166/113', '0106000020E610000001000000010300000001000000050000006514FCE15AA34BC011F5386F4A3726C035C0A027D52B4BC031FAEA60C77E26C00E0494C695454BC0CC4D6CCD224928C03D58EF801BBD4BC0AB48BADBA50128C06514FCE15AA34BC011F5386F4A3726C0', 557, 557, 2662, -11.6454000000000004, -54.8648999999999987, 'S 11 38 43', 'O 54 51 53', 166, 113);
INSERT INTO bdc.mux_grid VALUES ('166/114', '0106000020E610000001000000010300000001000000050000002CBC706F20BD4BC03FDA9AE8A20128C09C4DBC519F454BC08FA022181D4928C0D46F9C737D5F4BC064F4F8CA65132AC066DE5091FED64BC0142E719BEBCB29C02CBC706F20BD4BC03FDA9AE8A20128C0', 558, 558, 2663, -12.5404999999999998, -55.0668000000000006, 'S 12 32 25', 'O 55 04 00', 166, 114);
INSERT INTO bdc.mux_grid VALUES ('166/115', '0106000020E610000001000000010300000001000000050000000BEF47ED03D74BC04F94D966E8CB29C07DA060D0875F4BC05F8350985F132AC0ACF502F885794BC099F2952094DD2BC03944EA1402F14BC089031FEF1C962BC00BEF47ED03D74BC04F94D966E8CB29C0', 559, 559, 2665, -13.4354999999999993, -55.269599999999997, 'S 13 26 07', 'O 55 16 10', 166, 115);
INSERT INTO bdc.mux_grid VALUES ('166/116', '0106000020E61000000100000001030000000100000005000000C19B10E107F14BC073FF6D7719962BC0D4AAAA2B91794BC02E52666D8DDD2BC0A51BB5ECB1934BC097471B58ACA72DC0920C1BA2280B4CC0DDF4226238602DC0C19B10E107F14BC073FF6D7719962BC0', 560, 560, 2666, -14.3302999999999994, -55.4735000000000014, 'S 14 19 49', 'O 55 28 24', 166, 116);
INSERT INTO bdc.mux_grid VALUES ('166/117', '0106000020E610000001000000010300000001000000050000009F016BE12E0B4CC03D8F90A534602DC0C44304FDBD934BC01CB1F120A5A72DC0FA4D77FD03AE4BC06163B5F8AC712FC0D50BDEE174254CC08241547D3C2A2FC09F016BE12E0B4CC03D8F90A534602DC0', 561, 561, 2667, -15.2249999999999996, -55.6784000000000034, 'S 15 13 29', 'O 55 40 42', 166, 117);
INSERT INTO bdc.mux_grid VALUES ('166/118', '0106000020E610000001000000010300000001000000050000006C0C96977B254CC031C9EF79382A2FC076A0B4F010AE4BC0C2D6D039A5712FC0AE478AEA7EC84BC00F544943CA9D30C0A4B36B91E93F4CC049CD58E3137A30C06C0C96977B254CC031C9EF79382A2FC0', 562, 562, 2670, -16.1193999999999988, -55.8845999999999989, 'S 16 07 09', 'O 55 53 04', 166, 118);
INSERT INTO bdc.mux_grid VALUES ('166/119', '0106000020E610000001000000010300000001000000050000007AFC11C1F03F4CC0B6B52FBD117A30C0666586C78CC84BC043D4EF1DC69D30C0163E688A25E34BC0AE6044C1B08231C02BD5F383895A4CC020428460FC5E31C07AFC11C1F03F4CC0B6B52FBD117A30C0', 563, 563, 2671, -17.0137, -56.0921000000000021, 'S 17 00 49', 'O 56 05 31', 166, 119);
INSERT INTO bdc.mux_grid VALUES ('166/120', '0106000020E61000000100000001030000000100000005000000F4865A31915A4CC000CBBF14FA5E31C0958B855834E34BC07E51CE53AC8231C04E389CCBFAFD4BC0337FD834896732C0AD3371A457754CC0B6F8C9F5D64332C0F4865A31915A4CC000CBBF14FA5E31C0', 564, 564, 2672, -17.9076999999999984, -56.3008999999999986, 'S 17 54 27', 'O 56 18 03', 166, 120);
INSERT INTO bdc.mux_grid VALUES ('166/121', '0106000020E6100000010000000103000000010000000500000026D3BAD35F754CC047932D83D44332C04880D7920AFE4BC0185EE27C846732C09C2DB6B601194CC0656C7DDA524C33C07B8099F756904CC094A1C8E0A22833C026D3BAD35F754CC047932D83D44332C0', 565, 565, 2673, -18.8016000000000005, -56.5112000000000023, 'S 18 48 05', 'O 56 30 40', 166, 121);
INSERT INTO bdc.mux_grid VALUES ('166/122', '0106000020E61000000100000001030000000100000005000000C0E63DAD5F904CC05F3AFE45A02833C04A1BB07F12194CC0ACB472D54D4C33C0BEC05E703D344CC04EDF59EC0C3134C0378CEC9D8AAB4CC00065E55C5F0D34C0C0E63DAD5F904CC05F3AFE45A02833C0', 566, 566, 2674, -19.6951000000000001, -56.722999999999999, 'S 19 41 42', 'O 56 43 22', 166, 122);
INSERT INTO bdc.mux_grid VALUES ('166/123', '0106000020E610000001000000010300000001000000050000001455BEDE93AB4CC00CC47B985C0D34C0554866444F344CC036ED7197073134C0D6B58D3BB14F4CC0BF8E01A2B61535C095C2E5D5F5C64CC093650BA30BF234C01455BEDE93AB4CC00CC47B985C0D34C0', 567, 567, 2676, -20.5884999999999998, -56.9365000000000023, 'S 20 35 18', 'O 56 56 11', 166, 123);
INSERT INTO bdc.mux_grid VALUES ('166/124', '0106000020E61000000100000001030000000100000005000000C84118A7FFC64CC0446674B308F234C0217FAB24C44F4CC07E353CFAB01535C03687E67B606B4CC06ECB2C304FFA35C0DC4953FE9BE24CC033FC64E9A6D635C0C84118A7FFC64CC0446674B308F234C0', 568, 568, 2677, -21.4816000000000003, -57.1518000000000015, 'S 21 28 53', 'O 57 09 06', 166, 124);
INSERT INTO bdc.mux_grid VALUES ('166/125', '0106000020E6100000010000000103000000010000000500000064148165A6E24CC0DE98F3CCA3D635C00C73E984746B4CC089964E3249FA35C07FD33EB84E874CC0F31769C8D5DE36C0D774D69880FE4CC0471A0E6330BB36C064148165A6E24CC0DE98F3CCA3D635C0', 569, 569, 2678, -22.3744000000000014, -57.3688999999999965, 'S 22 22 27', 'O 57 22 08', 166, 125);
INSERT INTO bdc.mux_grid VALUES ('166/126', '0106000020E61000000100000001030000000100000005000000F68D089C8BFE4CC0D246F4172DBB36C00BB8C9EC63874CC0B12FF770CFDE36C0B5BD529D7FA34CC05F11C29849C337C0A293914CA71A4DC08028BF3FA79F37C0F68D089C8BFE4CC0D246F4172DBB36C0', 570, 570, 2681, -23.2669999999999995, -57.588000000000001, 'S 23 16 01', 'O 57 35 16', 166, 126);
INSERT INTO bdc.mux_grid VALUES ('166/127', '0106000020E61000000100000001030000000100000005000000534C47F2B21A4DC0AC770BC4A39F37C0B574EB0996A34CC029BAFDE342C337C048BEAB00F7BF4CC00DFA61CBA9A738C0E59507E913374DC090B76FAB0A8438C0534C47F2B21A4DC0AC770BC4A39F37C0', 571, 571, 2682, -24.1593000000000018, -57.809199999999997, 'S 24 09 33', 'O 57 48 32', 166, 127);
INSERT INTO bdc.mux_grid VALUES ('166/128', '0106000020E6100000010000000103000000010000000500000069323F3820374DC0F5C40AFD068438C0F8ACCBB20EC04CC0CEA243B5A2A738C01EE2BEE3B8DC4CC027132986F58B39C08E673269CA534DC04F35F0CD596839C069323F3820374DC0F5C40AFD068438C0', 572, 572, 2683, -25.0512000000000015, -58.0324999999999989, 'S 25 03 04', 'O 58 01 57', 166, 128);
INSERT INTO bdc.mux_grid VALUES ('166/129', '0106000020E61000000100000001030000000100000005000000D79B7269D7534DC023CF99EA556839C03D1CE5E9D1DC4CC0CFE85A0AEE8B39C09CF04777C9F94CC0B0EF3AEA2B703AC03570D5F6CE704DC005D679CA934C3AC0D79B7269D7534DC023CF99EA556839C0', 573, 573, 2684, -25.9429000000000016, -58.2582000000000022, 'S 25 56 34', 'O 58 15 29', 166, 129);
INSERT INTO bdc.mux_grid VALUES ('166/130', '0106000020E61000000100000001030000000100000005000000DCCE37B0DC704DC05FDEC5AF8F4C3AC0B6200DE1E3F94CC01BE9120424703AC0E488E71E2D174DC0F9BE80134C543BC00A3712EE258E4DC03DB433BFB7303BC0DCCE37B0DC704DC05FDEC5AF8F4C3AC0', 574, 574, 2686, -26.8341999999999992, -58.4864000000000033, 'S 26 50 03', 'O 58 29 11', 166, 130);
INSERT INTO bdc.mux_grid VALUES ('166/131', '0106000020E6100000010000000103000000010000000500000067A84E69348E4DC045B3866AB3303BC061D413FD48174DC0FB10FABD43543BC09CF80A75E8344DC072891F1855383CC0A2CC45E1D3AB4DC0BB2BACC4C4143CC067A84E69348E4DC045B3866AB3303BC0', 575, 575, 2687, -27.7251000000000012, -58.7171999999999983, 'S 27 43 30', 'O 58 43 01', 166, 131);
INSERT INTO bdc.mux_grid VALUES ('166/132', '0106000020E61000000100000001030000000100000005000000D82ABF27E3AB4DC04D8A3733C0143CC0270CAED905354DC0BF75D34D4C383CC0B938254F00534DC0A52AE107461C3DC06B57369DDDC94DC0343F45EDB9F83CC0D82ABF27E3AB4DC04D8A3733C0143CC0', 576, 576, 2688, -28.6157000000000004, -58.9506999999999977, 'S 28 36 56', 'O 58 57 02', 166, 132);
INSERT INTO bdc.mux_grid VALUES ('166/133', '0106000020E61000000100000001030000000100000005000000BD5108B9EDC94DC0AF1F031CB5F83CC007C0B04D1F534DC07E15FFC23C1C3DC0FC6341C279714DC05ABA8EEB1D003EC0B2F5982D48E84DC08BC4924496DC3DC0BD5108B9EDC94DC0AF1F031CB5F83CC0', 577, 577, 2689, -29.5060000000000002, -59.1869999999999976, 'S 29 30 21', 'O 59 11 13', 166, 133);
INSERT INTO bdc.mux_grid VALUES ('166/134', '0106000020E610000001000000010300000001000000050000000260A72959E84DC0986E413091DC3DC06E30A66F9A714DC0BB72D32514003EC03EE3F7275A904DC0D3EC3AC4DBE33EC0D312F9E118074EC0B2E8A8CE58C03EC00260A72959E84DC0986E413091DC3DC0', 578, 578, 2691, -30.3958000000000013, -59.4264999999999972, 'S 30 23 44', 'O 59 25 35', 166, 134);
INSERT INTO bdc.mux_grid VALUES ('166/135', '0106000020E610000001000000010300000001000000050000007EC300CA2A074EC006BEC57353C03EC06F0BC69A7C904DC03511E776D1E33EC06C9AD023A7AF4DC063CA7A8A7EC73FC07C520B5355264EC03577598700A43FC07EC300CA2A074EC006BEC57353C03EC0', 579, 579, 2693, -31.2852999999999994, -59.6691000000000003, 'S 31 17 06', 'O 59 40 08', 166, 135);
INSERT INTO bdc.mux_grid VALUES ('166/136', '0106000020E6100000010000000103000000010000000500000007C9B43368264EC0A15F1BE2FAA33FC0C3EA5A74CBAF4DC0722F48AE73C73FC0D7991DA966CF4DC01A78C596825540C01C78776803464EC03010AF30C64340C007C9B43368264EC0A15F1BE2FAA33FC0', 580, 580, 2694, -32.1743000000000023, -59.9151999999999987, 'S 32 10 27', 'O 59 54 54', 166, 136);
INSERT INTO bdc.mux_grid VALUES ('166/137', '0106000020E610000001000000010300000001000000050000009E726B4F17464EC0FEB0D736C34340C0B6B9A0F18CCF4DC0FE7550DD7C5540C0CF325B019FEF4DC04AA12F4937C740C0B7EB255F29664EC04CDCB6A27DB540C09E726B4F17464EC0FEB0D736C34340C0', 581, 581, 2695, -33.0628999999999991, -60.1647999999999996, 'S 33 03 46', 'O 60 09 53', 166, 137);
INSERT INTO bdc.mux_grid VALUES ('166/138', '0106000020E61000000100000001030000000100000005000000DF34245B3E664EC0F092727F7AB540C0B4E9285EC7EF4DC0E0DD224031C740C077D923D356104EC0126A4DC9DC3841C0A2241FD0CD864EC0221F9D08262741C0DF34245B3E664EC0F092727F7AB540C0', 582, 582, 2696, -33.9510000000000005, -60.4181999999999988, 'S 33 57 03', 'O 60 25 05', 166, 138);
INSERT INTO bdc.mux_grid VALUES ('166/139', '0106000020E610000001000000010300000001000000050000005DD117F1E3864EC0D4D489B9222741C0AEF6D26281104EC036F7156CD63841C05F07C82995314EC06EB4B67D72AA41C00EE20CB8F7A74EC00C922ACBBE9841C05DD117F1E3864EC0D4D489B9222741C0', 583, 583, 2697, -34.8387000000000029, -60.6756000000000029, 'S 34 50 19', 'O 60 40 32', 166, 139);
INSERT INTO bdc.mux_grid VALUES ('166/140', '0106000020E6100000010000000103000000010000000500000059563C0F0FA84EC0747FB44DBB9841C0FE73690DC2314EC010D362C76BAA41C020499C7D61534EC066D829C6F71B42C07B2B6F7FAEC94EC0CA847B4C470A42C059563C0F0FA84EC0747FB44DBB9841C0', 584, 584, 2699, -35.7257999999999996, -60.9371999999999971, 'S 35 43 33', 'O 60 56 13', 166, 140);
INSERT INTO bdc.mux_grid VALUES ('166/141', '0106000020E61000000100000001030000000100000005000000A02F7D1FC7C94EC02D8CD89D430A42C061ECF5D890534EC0262A60B1F01B42C035F811BDC3754EC0EA78DBFA6B8D42C0743B9903FAEB4EC0F0DA53E7BE7B42C0A02F7D1FC7C94EC02D8CD89D430A42C0', 585, 585, 2700, -36.6124999999999972, -61.2032000000000025, 'S 36 36 45', 'O 61 12 11', 166, 141);
INSERT INTO bdc.mux_grid VALUES ('166/142', '0106000020E61000000100000001030000000100000005000000249ABB0014EC4EC0085B7E04BB7B42C0C926E0B6F5754EC05437D181648D42C01BBCB156C4984EC0F038B46BCEFE42C0762F8DA0E20E4FC0A45C61EE24ED42C0249ABB0014EC4EC0085B7E04BB7B42C0', 586, 586, 2701, -37.4986000000000033, -61.4739000000000004, 'S 37 29 55', 'O 61 28 26', 166, 142);
INSERT INTO bdc.mux_grid VALUES ('166/143', '0106000020E61000000100000001030000000100000005000000AB36AE10FE0E4FC0C46E12D420ED42C0A0FBEF18F9984EC018542288C6FE42C0F9E211446CBC4EC0183C7A5F1E7043C0011ED03B71324FC0C6566AAB785E43C0AB36AE10FE0E4FC0C46E12D420ED42C0', 587, 587, 2703, -38.3841999999999999, -61.7496000000000009, 'S 38 23 03', 'O 61 44 58', 166, 143);
INSERT INTO bdc.mux_grid VALUES ('166/96', '0106000020E610000001000000010300000001000000050000001A85B6D16EF649C0CE6C3D2B1A7D1040A00C059BD07E49C0EA90F7FA05DC0F4087F61AAEF49749C068993A0400B10840016FCCE4920F4AC018E2BD5F2ECF09401A85B6D16EF649C0CE6C3D2B1A7D1040', 588, 588, 2749, 3.58429999999999982, -51.5112000000000023, 'N 03 35 03', 'O 51 30 40', 166, 96);
INSERT INTO bdc.mux_grid VALUES ('166/97', '0106000020E6100000010000000103000000010000000500000037C41C64910F4AC0816C65C72ACF0940039BB6EFF19749C0DA19C973F9B008405E9326140EB149C0D8641597DE85014092BC8C88AD284AC07FB7B1EA0FA4024037C41C64910F4AC0816C65C72ACF0940', 589, 589, 2750, 2.68829999999999991, -51.7073999999999998, 'N 02 41 17', 'O 51 42 26', 166, 97);
INSERT INTO bdc.mux_grid VALUES ('166/98', '0106000020E61000000100000001030000000100000005000000E2250966AC284AC022D2A6330DA402401B291F090CB149C0823FC2B3D985014001265C5F22CA49C0A312141E5FB5F43FC82246BCC2414AC0E337DD1DC6F1F63FE2250966AC284AC022D2A6330DA40240', 590, 590, 2751, 1.79220000000000002, -51.9035000000000011, 'N 01 47 31', 'O 51 54 12', 166, 98);
INSERT INTO bdc.mux_grid VALUES ('166/99', '0106000020E61000000100000001030000000100000005000000072A64F7C1414AC09A06CC6FC2F1F63F0932B80621CA49C04FBE00AD58B5F43F21675EAC33E349C06D3A4E30C47BD93F205F0A9DD45A4AC0C2ADBD9DB536E13F072A64F7C1414AC09A06CC6FC2F1F63F', 591, 591, 2753, 0.896100000000000008, -52.0994000000000028, 'N 00 53 45', 'O 52 05 57', 166, 99);
INSERT INTO bdc.mux_grid VALUES ('167/100', '0106000020E6100000010000000103000000010000000500000087BF11295ED64AC0B20D24BEB136E13FEC331FF9BC5E4AC099AC07B6B77BD93F5651FE09CE774AC02D59525307DEDFBFF1DCF0396FEF4AC062EA118D5BECD6BF87BF11295ED64AC0B20D24BEB136E13F', 592, 592, 2754, 0, -53.2603999999999971, 'N 00 00 00', 'O 53 15 37', 167, 100);
INSERT INTO bdc.mux_grid VALUES ('167/101', '0106000020E61000000100000001030000000100000005000000C584652F6FEF4AC07C75E2565CECD6BF81A98914CE774AC00CCE818906DEDFBFAB41ADABDF904AC08CFDAB51EE4DF6BFEF1C89C680084BC0682704C58311F4BFC584652F6FEF4AC07C75E2565CECD6BF', 593, 593, 2756, -0.896100000000000008, -53.4562000000000026, 'S 00 53 45', 'O 53 27 22', 167, 101);
INSERT INTO bdc.mux_grid VALUES ('167/102', '0106000020E6100000010000000103000000010000000500000027690B1981084BC0B3BC373A8211F4BF3D8DAD67E0904AC00C261ACEEA4DF6BFE3B164A0F4A94AC0045B579B245202C0CE8DC25195214BC058266651F03301C027690B1981084BC0B3BC373A8211F4BF', 594, 594, 2757, -1.79220000000000002, -53.6520999999999972, 'S 01 47 31', 'O 53 39 07', 167, 102);
INSERT INTO bdc.mux_grid VALUES ('167/103', '0106000020E610000001000000010300000001000000050000009AA6790196214BC0C6FB01ADEE3301C0DA5C330EF6A94AC0C5A42930215202C0E58118050FC34AC09CF73AA7437D09C0A5CB5EF8AE3A4BC09C4E1324115F08C09AA6790196214BC0C6FB01ADEE3301C0', 595, 595, 2758, -2.68829999999999991, -53.8481000000000023, 'S 02 41 17', 'O 53 50 53', 167, 103);
INSERT INTO bdc.mux_grid VALUES ('167/104', '0106000020E6100000010000000103000000010000000500000049349E05B03A4BC0DC61E99F0E5F08C0EDBE632511C34AC0FEB307913E7D09C07AF265F930DC4AC0AAF04658275410C0D567A0D9CF534BC0308F6FBF1E8A0FC049349E05B03A4BC0DC61E99F0E5F08C0', 596, 596, 2759, -3.58429999999999982, -54.0444000000000031, 'S 03 35 03', 'O 54 02 39', 167, 104);
INSERT INTO bdc.mux_grid VALUES ('167/105', '0106000020E610000001000000010300000001000000050000008454E844D1534BC050274D5A1B8A0FC0346C31CD33DC4AC04DE973F6235410C032F59FA05CF54AC071BDD50CA0E913C082DD5618FA6C4BC0CB6788C3895A13C08454E844D1534BC050274D5A1B8A0FC0', 597, 597, 2760, -4.48029999999999973, -54.2409000000000034, 'S 04 28 49', 'O 54 14 27', 167, 105);
INSERT INTO bdc.mux_grid VALUES ('167/106', '0106000020E6100000010000000103000000010000000500000027B754E2FB6C4BC03286AB9F875A13C035D7452960F54AC03237ABD29BE913C0A850DF22940E4BC01AE76221097F17C09B30EEDB2F864BC0193663EEF4EF16C027B754E2FB6C4BC03286AB9F875A13C0', 598, 598, 2762, -5.37619999999999987, -54.4376999999999995, 'S 05 22 34', 'O 54 26 15', 167, 106);
INSERT INTO bdc.mux_grid VALUES ('167/107', '0106000020E610000001000000010300000001000000050000009A477D0532864BC04B4D3458F2EF16C098A91162980E4BC0A6A6D90C047F17C00FB617AED9274BC0B55CB3C45F141BC011548351739F4BC05A030E104E851AC09A477D0532864BC04B4D3458F2EF16C0', 599, 599, 2763, -6.27210000000000001, -54.6349000000000018, 'S 06 16 19', 'O 54 38 05', 167, 107);
INSERT INTO bdc.mux_grid VALUES ('167/108', '0106000020E6100000010000000103000000010000000500000052C3ADDB759F4BC0BFC04E064B851AC03536E2A5DE274BC075EE58D359141BC0B2EF32772F414BC00D28F423A1A91EC0CE7CFEACC6B84BC058FAE956921A1EC052C3ADDB759F4BC0BFC04E064B851AC0', 600, 600, 2764, -7.16790000000000038, -54.8325000000000031, 'S 07 10 04', 'O 54 49 57', 167, 108);
INSERT INTO bdc.mux_grid VALUES ('167/109', '0106000020E61000000100000001030000000100000005000000413EFE98C9B84BC086C722D88E1A1EC0DC04FD2935414BC05E5AE8529AA91EC01F5733BB975A4BC040B23835651F21C08590342A2CD24BC0D4E8D577DFD720C0413EFE98C9B84BC086C722D88E1A1EC0', 601, 601, 2766, -8.06359999999999921, -55.0307000000000031, 'S 08 03 49', 'O 55 01 50', 167, 109);
INSERT INTO bdc.mux_grid VALUES ('167/110', '0106000020E61000000100000001030000000100000005000000CAC574792FD24BC09D25157DDDD720C0D2ACC22B9E5A4BC0EFA4315B611F21C098D45EC014744BC0088DA360ECE922C090ED100EA6EB4BC0B50D878268A222C0CAC574792FD24BC09D25157DDDD720C0', 602, 602, 2768, -8.95919999999999916, -55.2295000000000016, 'S 08 57 33', 'O 55 13 46', 167, 110);
INSERT INTO bdc.mux_grid VALUES ('167/111', '0106000020E61000000100000001030000000100000005000000AA5D2FC2A9EB4BC036A4714B66A222C04A39DAF11B744BC032C93813E8E922C094B173D7A88D4BC0728D85A764B424C0F3D5C8A736054CC07568BEDFE26C24C0AA5D2FC2A9EB4BC036A4714B66A222C0', 603, 603, 2769, -9.85479999999999912, -55.4288999999999987, 'S 09 51 17', 'O 55 25 44', 167, 111);
INSERT INTO bdc.mux_grid VALUES ('167/112', '0106000020E61000000100000001030000000100000005000000C7A497C23A054CC08E8A3D6BE06C24C01F6966CDB08D4BC0206D98E45FB424C07CA0E85C56A74BC03F73B79BCC7E26C025DC1952E01E4CC0AD905C224D3726C0C7A497C23A054CC08E8A3D6BE06C24C0', 604, 604, 2770, -10.7501999999999995, -55.6291000000000011, 'S 10 45 00', 'O 55 37 44', 167, 112);
INSERT INTO bdc.mux_grid VALUES ('167/113', '0106000020E61000000100000001030000000100000005000000047CA1D5E41E4CC0F9F4386F4A3726C0D427461B5FA74BC01AFAEA60C77E26C0A36B39BA1FC14BC0164D6CCD224928C0D3BF9474A5384CC0F647BADBA50128C0047CA1D5E41E4CC0F9F4386F4A3726C0', 605, 605, 2771, -11.6454000000000004, -55.8301000000000016, 'S 11 38 43', 'O 55 49 48', 167, 113);
INSERT INTO bdc.mux_grid VALUES ('167/114', '0106000020E61000000100000001030000000100000005000000D5231663AA384CC081D99AE8A20128C022B5614529C14BC0E69F22181D4928C068D7416707DB4BC09DF4F8CA65132AC01946F68488524CC0382E719BEBCB29C0D5231663AA384CC081D99AE8A20128C0', 606, 606, 2773, -12.5404999999999998, -56.0319000000000003, 'S 12 32 25', 'O 56 01 54', 167, 114);
INSERT INTO bdc.mux_grid VALUES ('167/115', '0106000020E61000000100000001030000000100000005000000B556EDE08D524CC07B94D966E8CB29C0280806C411DB4BC08B8350985F132AC0555DA8EB0FF54BC0A8F2952094DD2BC0E1AB8F088C6C4CC098031FEF1C962BC0B556EDE08D524CC07B94D966E8CB29C0', 607, 607, 2774, -13.4354999999999993, -56.2347999999999999, 'S 13 26 07', 'O 56 14 05', 167, 115);
INSERT INTO bdc.mux_grid VALUES ('167/116', '0106000020E610000001000000010300000001000000050000006203B6D4916C4CC083FF6D7719962BC05312501F1BF54BC05252666D8DDD2BC029835AE03B0F4CC01E481B58ACA72DC03774C095B2864CC050F5226238602DC06203B6D4916C4CC083FF6D7719962BC0', 608, 608, 2775, -14.3302999999999994, -56.438600000000001, 'S 14 19 49', 'O 56 26 18', 167, 116);
INSERT INTO bdc.mux_grid VALUES ('167/117', '0106000020E610000001000000010300000001000000050000003D6910D5B8864CC0B68F90A534602DC085ABA9F0470F4CC080B1F120A5A72DC0ACB51CF18D294CC0A962B5F8AC712FC0647383D5FEA04CC0DF40547D3C2A2FC03D6910D5B8864CC0B68F90A534602DC0', 609, 609, 2776, -15.2249999999999996, -56.6435999999999993, 'S 15 13 29', 'O 56 38 36', 167, 117);
INSERT INTO bdc.mux_grid VALUES ('167/118', '0106000020E6100000010000000103000000010000000500000000743B8B05A14CC087C8EF79382A2FC009085AE49A294CC016D6D039A5712FC04AAF2FDE08444CC0FC534943CA9D30C0401B118573BB4CC034CD58E3137A30C000743B8B05A14CC087C8EF79382A2FC0', 610, 610, 2778, -16.1193999999999988, -56.8498000000000019, 'S 16 07 09', 'O 56 50 59', 167, 118);
INSERT INTO bdc.mux_grid VALUES ('167/119', '0106000020E610000001000000010300000001000000050000002964B7B47ABB4CC09BB52FBD117A30C0F2CC2BBB16444CC035D4EF1DC69D30C0A8A50D7EAF5E4CC0D16044C1B08231C0DF3C997713D64CC038428460FC5E31C02964B7B47ABB4CC09BB52FBD117A30C0', 611, 611, 2779, -17.0137, -57.0572000000000017, 'S 17 00 49', 'O 57 03 25', 167, 119);
INSERT INTO bdc.mux_grid VALUES ('167/120', '0106000020E610000001000000010300000001000000050000007CEEFF241BD64CC024CBBF14FA5E31C03EF32A4CBE5E4CC09851CE53AC8231C0F59F41BF84794CC03F7FD834896732C0329B1698E1F04CC0CBF8C9F5D64332C07CEEFF241BD64CC024CBBF14FA5E31C0', 612, 612, 2780, -17.9076999999999984, -57.2659999999999982, 'S 17 54 27', 'O 57 15 57', 167, 120);
INSERT INTO bdc.mux_grid VALUES ('167/121', '0106000020E61000000100000001030000000100000005000000BB3A60C7E9F04CC058932D83D44332C020E87C8694794CC0155EE27C846732C065955BAA8B944CC0D56B7DDA524C33C0FFE73EEBE00B4DC016A1C8E0A22833C0BB3A60C7E9F04CC058932D83D44332C0', 613, 613, 2781, -18.8016000000000005, -57.4763000000000019, 'S 18 48 05', 'O 57 28 34', 167, 121);
INSERT INTO bdc.mux_grid VALUES ('167/122', '0106000020E61000000100000001030000000100000005000000104EE3A0E90B4DC0EF39FE45A02833C0238355739C944CC015B472D54D4C33C0A6280464C7AF4CC028DF59EC0C3134C093F3919114274DC00265E55C5F0D34C0104EE3A0E90B4DC0EF39FE45A02833C0', 614, 614, 2783, -19.6951000000000001, -57.6882000000000019, 'S 19 41 42', 'O 57 41 17', 167, 122);
INSERT INTO bdc.mux_grid VALUES ('167/123', '0106000020E610000001000000010300000001000000050000009DBC63D21D274DC0FFC37B985C0D34C023B00B38D9AF4CC018ED7197073134C0A31D332F3BCB4CC0928E01A2B61535C01C2A8BC97F424DC079650BA30BF234C09DBC63D21D274DC0FFC37B985C0D34C0', 615, 615, 2784, -20.5884999999999998, -57.9016999999999982, 'S 20 35 18', 'O 57 54 06', 167, 123);
INSERT INTO bdc.mux_grid VALUES ('167/124', '0106000020E6100000010000000103000000010000000500000050A9BD9A89424DC0286674B308F234C0F1E650184ECB4CC050353CFAB01535C013EF8B6FEAE64CC0AFCB2C304FFA35C073B1F8F1255E4DC087FC64E9A6D635C050A9BD9A89424DC0286674B308F234C0', 616, 616, 2785, -21.4816000000000003, -58.1169000000000011, 'S 21 28 53', 'O 58 07 00', 167, 124);
INSERT INTO bdc.mux_grid VALUES ('167/125', '0106000020E61000000100000001030000000100000005000000E27B2659305E4DC03B99F3CCA3D635C014DB8E78FEE64CC0C0964E3249FA35C0863BE4ABD8024DC0181869C8D5DE36C053DC7B8C0A7A4DC0951A0E6330BB36C0E27B2659305E4DC03B99F3CCA3D635C0', 617, 617, 2786, -22.3744000000000014, -58.3340000000000032, 'S 22 22 27', 'O 58 20 02', 167, 125);
INSERT INTO bdc.mux_grid VALUES ('167/126', '0106000020E610000001000000010300000001000000050000008CF5AD8F157A4DC01A47F4172DBB36C0E41F6FE0ED024DC0E62FF770CFDE36C07B25F890091F4DC00411C29849C337C022FB364031964DC03828BF3FA79F37C08CF5AD8F157A4DC01A47F4172DBB36C0', 618, 618, 2789, -23.2669999999999995, -58.5531000000000006, 'S 23 16 01', 'O 58 33 11', 167, 126);
INSERT INTO bdc.mux_grid VALUES ('167/127', '0106000020E610000001000000010300000001000000050000001FB4ECE53C964DC04E770BC4A39F37C03BDC90FD1F1F4DC0E1B9FDE342C337C0CD2551F4803B4DC0B6F961CBA9A738C0AFFDACDC9DB24DC023B76FAB0A8438C01FB4ECE53C964DC04E770BC4A39F37C0', 619, 619, 2790, -24.1593000000000018, -58.7742999999999967, 'S 24 09 33', 'O 58 46 27', 167, 127);
INSERT INTO bdc.mux_grid VALUES ('167/128', '0106000020E610000001000000010300000001000000050000001F9AE42BAAB24DC08DC40AFD068438C0B01471A6983B4DC068A243B5A2A738C0E24964D742584DC032132986F58B39C052CFD75C54CF4DC05735F0CD596839C01F9AE42BAAB24DC08DC40AFD068438C0', 620, 620, 2791, -25.0512000000000015, -58.9977000000000018, 'S 25 03 04', 'O 58 59 51', 167, 128);
INSERT INTO bdc.mux_grid VALUES ('167/129', '0106000020E610000001000000010300000001000000050000005A03185D61CF4DC042CF99EA556839C0C0838ADD5B584DC0EDE85A0AEE8B39C01D58ED6A53754DC0BFEF3AEA2B703AC0B5D77AEA58EC4DC012D679CA934C3AC05A03185D61CF4DC042CF99EA556839C0', 621, 621, 2793, -25.9429000000000016, -59.223399999999998, 'S 25 56 34', 'O 59 13 24', 167, 129);
INSERT INTO bdc.mux_grid VALUES ('167/130', '0106000020E61000000100000001030000000100000005000000B336DDA366EC4DC054DEC5AF8F4C3AC04888B2D46D754DC026E9120424703AC072F08C12B7924DC0F3BE80134C543BC0DE9EB7E1AF094EC021B433BFB7303BC0B336DDA366EC4DC054DEC5AF8F4C3AC0', 622, 622, 2794, -26.8341999999999992, -59.4515000000000029, 'S 26 50 03', 'O 59 27 05', 167, 130);
INSERT INTO bdc.mux_grid VALUES ('167/131', '0106000020E61000000100000001030000000100000005000000E00FF45CBE094EC043B3866AB3303BC01E3CB9F0D2924DC0E710FABD43543BC06960B06872B04DC0CE891F1855383CC02934EBD45D274EC02A2CACC4C4143CC0E00FF45CBE094EC043B3866AB3303BC0', 623, 623, 2795, -27.7251000000000012, -59.6822999999999979, 'S 27 43 30', 'O 59 40 56', 167, 131);
INSERT INTO bdc.mux_grid VALUES ('167/132', '0106000020E610000001000000010300000001000000050000006592641B6D274EC0BD8A3733C0143CC0FB7353CD8FB04DC01C76D34D4C383CC08CA0CA428ACE4DC0F32AE107461C3DC0F6BEDB9067454EC0953F45EDB9F83CC06592641B6D274EC0BD8A3733C0143CC0', 624, 624, 2796, -28.6157000000000004, -59.9157999999999973, 'S 28 36 56', 'O 59 54 56', 167, 132);
INSERT INTO bdc.mux_grid VALUES ('167/133', '0106000020E6100000010000000103000000010000000500000099B9ADAC77454EC0F81F031CB5F83CC09C275641A9CE4DC0DD15FFC23C1C3DC08FCBE6B503ED4DC0A9BA8EEB1D003EC08C5D3E21D2634EC0C4C4924496DC3DC099B9ADAC77454EC0F81F031CB5F83CC0', 625, 625, 2798, -29.5060000000000002, -60.1522000000000006, 'S 29 30 21', 'O 60 09 07', 167, 133);
INSERT INTO bdc.mux_grid VALUES ('167/134', '0106000020E610000001000000010300000001000000050000009DC74C1DE3634EC0E56E413091DC3DC04D984B6324ED4DC0F672D32514003EC01D4B9D1BE40B4EC0FDEC3AC4DBE33EC06C7A9ED5A2824EC0EDE8A8CE58C03EC09DC74C1DE3634EC0E56E413091DC3DC0', 626, 626, 2799, -30.3958000000000013, -60.3915999999999968, 'S 30 23 44', 'O 60 23 29', 167, 134);
INSERT INTO bdc.mux_grid VALUES ('167/135', '0106000020E610000001000000010300000001000000050000000E2BA6BDB4824EC044BEC57353C03EC0FD726B8E060C4EC07611E776D1E33EC00A027617312B4EC014CB7A8A7EC73FC01CBAB046DFA14EC0E377598700A43FC00E2BA6BDB4824EC044BEC57353C03EC0', 627, 627, 2801, -31.2852999999999994, -60.6343000000000032, 'S 31 17 06', 'O 60 38 03', 167, 135);
INSERT INTO bdc.mux_grid VALUES ('167/136', '0106000020E6100000010000000103000000010000000500000067305A27F2A14EC060601BE2FAA33FC0AE520068552B4EC00C3048AE73C73FC0BD01C39CF04A4EC05A78C596825540C078DF1C5C8DC14EC08410AF30C64340C067305A27F2A14EC060601BE2FAA33FC0', 628, 628, 2803, -32.1743000000000023, -60.8802999999999983, 'S 32 10 27', 'O 60 52 49', 167, 136);
INSERT INTO bdc.mux_grid VALUES ('167/137', '0106000020E6100000010000000103000000010000000500000015DA1043A1C14EC04EB1D736C34340C0712146E5164B4EC0427650DD7C5540C0779A00F5286B4EC048A12F4937C740C01B53CB52B3E14EC054DCB6A27DB540C015DA1043A1C14EC04EB1D736C34340C0', 629, 629, 2804, -33.0628999999999991, -61.1300000000000026, 'S 33 03 46', 'O 61 07 47', 167, 137);
INSERT INTO bdc.mux_grid VALUES ('167/138', '0106000020E61000000100000001030000000100000005000000839CC94EC8E14EC0F092727F7AB540C09C51CE51516B4EC0D4DD224031C740C04B41C9C6E08B4EC0BE694DC9DC3841C0308CC4C357024FC0DC1E9D08262741C0839CC94EC8E14EC0F092727F7AB540C0', 630, 630, 2805, -33.9510000000000005, -61.3834000000000017, 'S 33 57 03', 'O 61 23 00', 167, 138);
INSERT INTO bdc.mux_grid VALUES ('167/139', '0106000020E610000001000000010300000001000000050000001F39BDE46D024FC086D489B9222741C0E45D78560B8C4EC0FAF6156CD63841C0BB6E6D1D1FAD4EC0AAB4B67D72AA41C0F449B2AB81234FC036922ACBBE9841C01F39BDE46D024FC086D489B9222741C0', 631, 631, 2807, -34.8387000000000029, -61.6407000000000025, 'S 34 50 19', 'O 61 38 26', 167, 139);
INSERT INTO bdc.mux_grid VALUES ('167/140', '0106000020E61000000100000001030000000100000005000000E2BDE10299234FC0AA7FB44DBB9841C087DB0E014CAD4EC046D362C76BAA41C0A5B04171EBCE4EC094D829C6F71B42C00093147338454FC0FA847B4C470A42C0E2BDE10299234FC0AA7FB44DBB9841C0', 632, 632, 2808, -35.7257999999999996, -61.9022999999999968, 'S 35 43 33', 'O 61 54 08', 167, 140);
INSERT INTO bdc.mux_grid VALUES ('167/141', '0106000020E610000001000000010300000001000000050000008B97221351454FC04E8CD89D430A42C0C0539BCC1ACF4EC05C2A60B1F01B42C0955FB7B04DF14EC01879DBFA6B8D42C05EA33EF783674FC00ADB53E7BE7B42C08B97221351454FC04E8CD89D430A42C0', 633, 633, 2809, -36.6124999999999972, -62.1683999999999983, 'S 36 36 45', 'O 62 10 06', 167, 141);
INSERT INTO bdc.mux_grid VALUES ('167/142', '0106000020E61000000100000001030000000100000005000000CD0161F49D674FC02C5B7E04BB7B42C0EA8D85AA7FF14EC08A37D181648D42C03A23574A4E144FC01E39B46BCEFE42C01F9732946C8A4FC0C05C61EE24ED42C0CD0161F49D674FC02C5B7E04BB7B42C0', 634, 634, 2810, -37.4986000000000033, -62.4391000000000034, 'S 37 29 55', 'O 62 26 20', 167, 142);
INSERT INTO bdc.mux_grid VALUES ('167/143', '0106000020E610000001000000010300000001000000050000006D9E5304888A4FC0DE6E12D420ED42C06463950C83144FC030542288C6FE42C0B94AB737F6374FC02A3C7A5F1E7043C0C485752FFBAD4FC0D6566AAB785E43C06D9E5304888A4FC0DE6E12D420ED42C0', 635, 635, 2811, -38.3841999999999999, -62.7147000000000006, 'S 38 23 03', 'O 62 42 53', 167, 143);
INSERT INTO bdc.mux_grid VALUES ('167/144', '0106000020E61000000100000001030000000100000005000000E2FE5E2A18AE4FC00E621356745E43C01569F1EF2D384FC09E3A910A167043C07D918B094F5C4FC0840AE4125BE143C04A27F94339D24FC0F631665EB9CF43C0E2FE5E2A18AE4FC00E621356745E43C0', 636, 636, 2813, -39.2691999999999979, -62.9956000000000031, 'S 39 16 09', 'O 62 59 44', 167, 144);
INSERT INTO bdc.mux_grid VALUES ('167/145', '0106000020E61000000100000001030000000100000005000000675084E357D24FC0B0BE29CAB4CF43C07F0F38E9895C4FC02A843E4552E143C08EC7EFF462814FC06A2F92B7835244C076083CEF30F74FC0F0697D3CE64044C0675084E357D24FC0B0BE29CAB4CF43C0', 637, 637, 2815, -40.1535999999999973, -63.2820999999999998, 'S 40 09 13', 'O 63 16 55', 167, 145);
INSERT INTO bdc.mux_grid VALUES ('167/95', '0106000020E610000001000000010300000001000000050000005ABADC7ECC584AC0972846219212144015D9A8DB2FE149C00A4D2FD67C8313402C98BB015EFA49C069E6AA3B0EDC0F407279EFA4FA714AC0C14EEC681C7D10405ABADC7ECC584AC09728462192121440', 638, 638, 2858, 4.48029999999999973, -52.2798999999999978, 'N 04 28 49', 'O 52 16 47', 167, 95);
INSERT INTO bdc.mux_grid VALUES ('167/96', '0106000020E61000000100000001030000000100000005000000BAEC5BC5F8714AC0B56C3D2B1A7D10404974AA8E5AFA49C0D090F7FA05DC0F402D5EC0A17E134AC0DA993A0400B108409ED671D81C8B4AC075E2BD5F2ECF0940BAEC5BC5F8714AC0B56C3D2B1A7D1040', 639, 639, 2859, 3.58429999999999982, -52.4763999999999982, 'N 03 35 03', 'O 52 28 34', 167, 96);
INSERT INTO bdc.mux_grid VALUES ('167/97', '0106000020E61000000100000001030000000100000005000000D52BC2571B8B4AC0E06C65C72ACF0940A0025CE37B134AC03A1AC973F9B00840FDFACB07982C4AC0AE641597DE8501403124327C37A44AC055B7B1EA0FA40240D52BC2571B8B4AC0E06C65C72ACF0940', 640, 640, 2860, 2.68829999999999991, -52.6726000000000028, 'N 02 41 17', 'O 52 40 21', 167, 97);
INSERT INTO bdc.mux_grid VALUES ('167/98', '0106000020E61000000100000001030000000100000005000000878DAE5936A44AC0FED1A6330DA40240C490C4FC952C4AC06A3FC2B3D9850140A98D0153AC454AC0CA12141E5FB5F43F6C8AEBAF4CBD4AC0F337DD1DC6F1F63F878DAE5936A44AC0FED1A6330DA40240', 641, 641, 2862, 1.79220000000000002, -52.8686000000000007, 'N 01 47 31', 'O 52 52 07', 167, 98);
INSERT INTO bdc.mux_grid VALUES ('167/99', '0106000020E61000000100000001030000000100000005000000AA9109EB4BBD4AC0AE06CC6FC2F1F63FAC995DFAAA454AC064BE00AD58B5F43FC4CE03A0BD5E4AC0653A4E30C47BD93FC2C6AF905ED64AC0C5ADBD9DB536E13FAA9109EB4BBD4AC0AE06CC6FC2F1F63F', 642, 642, 2863, 0.896100000000000008, -53.0645000000000024, 'N 00 53 45', 'O 53 03 52', 167, 99);
INSERT INTO bdc.mux_grid VALUES ('168/100', '0106000020E610000001000000010300000001000000050000002827B71CE8514BC0940D24BEB136E13F8E9BC4EC46DA4AC0A0AC07B6B77BD93FF8B8A3FD57F34AC04A59525307DEDFBF9244962DF96A4BC0C2EA118D5BECD6BF2827B71CE8514BC0940D24BEB136E13F', 643, 643, 2864, 0, -54.2254999999999967, 'N 00 00 00', 'O 54 13 31', 168, 100);
INSERT INTO bdc.mux_grid VALUES ('168/101', '0106000020E6100000010000000103000000010000000500000066EC0A23F96A4BC0CB75E2565CECD6BF23112F0858F34AC03CCE818906DEDFBF4EA9529F690C4BC0B4FDAB51EE4DF6BF91842EBA0A844BC09C2704C58311F4BF66EC0A23F96A4BC0CB75E2565CECD6BF', 644, 644, 2867, -0.896100000000000008, -54.4213999999999984, 'S 00 53 45', 'O 54 25 16', 168, 101);
INSERT INTO bdc.mux_grid VALUES ('168/102', '0106000020E61000000100000001030000000100000005000000C7D0B00C0B844BC0F8BC373A8211F4BFDBF4525B6A0C4BC04E261ACEEA4DF6BF83190A947E254BC02B5B579B245202C06DF567451F9D4BC07E266651F03301C0C7D0B00C0B844BC0F8BC373A8211F4BF', 645, 645, 2868, -1.79220000000000002, -54.6173000000000002, 'S 01 47 31', 'O 54 37 02', 168, 102);
INSERT INTO bdc.mux_grid VALUES ('168/103', '0106000020E61000000100000001030000000100000005000000350E1FF51F9D4BC0F8FB01ADEE3301C07EC4D80180254BC0E5A42930215202C089E9BDF8983E4BC0B2F73AA7437D09C0403304EC38B64BC0C74E1324115F08C0350E1FF51F9D4BC0F8FB01ADEE3301C0', 646, 646, 2869, -2.68829999999999991, -54.8132999999999981, 'S 02 41 17', 'O 54 48 47', 168, 103);
INSERT INTO bdc.mux_grid VALUES ('168/104', '0106000020E61000000100000001030000000100000005000000EC9B43F939B64BC0F861E99F0E5F08C0902609199B3E4BC01DB407913E7D09C0185A0BEDBA574BC072F04658275410C074CF45CD59CF4BC0BD8E6FBF1E8A0FC0EC9B43F939B64BC0F861E99F0E5F08C0', 647, 647, 2870, -3.58429999999999982, -55.0095000000000027, 'S 03 35 03', 'O 55 00 34', 168, 104);
INSERT INTO bdc.mux_grid VALUES ('168/105', '0106000020E6100000010000000103000000010000000500000028BC8D385BCF4BC0D8264D5A1B8A0FC0CFD3D6C0BD574BC01BE973F6235410C0CC5C4594E6704BC031BDD50CA0E913C02545FC0B84E84BC0826788C3895A13C028BC8D385BCF4BC0D8264D5A1B8A0FC0', 648, 648, 2872, -4.48029999999999973, -55.2060000000000031, 'S 04 28 49', 'O 55 12 21', 168, 105);
INSERT INTO bdc.mux_grid VALUES ('168/106', '0106000020E61000000100000001030000000100000005000000CB1EFAD585E84BC0E685AB9F875A13C0C73EEB1CEA704BC0FC36ABD29BE913C039B884161E8A4BC09DE66221097F17C03D9893CFB9014CC0883563EEF4EF16C0CB1EFAD585E84BC0E685AB9F875A13C0', 649, 649, 2873, -5.37619999999999987, -55.4027999999999992, 'S 05 22 34', 'O 55 24 10', 168, 106);
INSERT INTO bdc.mux_grid VALUES ('168/107', '0106000020E610000001000000010300000001000000050000002EAF22F9BB014CC0CB4C3458F2EF16C03D11B755228A4BC011A6D90C047F17C0B81DBDA163A34BC0DD5CB3C45F141BC0A9BB2845FD1A4CC097030E104E851AC02EAF22F9BB014CC0CB4C3458F2EF16C0', 650, 650, 2874, -6.27210000000000001, -55.6000000000000014, 'S 06 16 19', 'O 55 36 00', 168, 107);
INSERT INTO bdc.mux_grid VALUES ('168/108', '0106000020E61000000100000001030000000100000005000000F22A53CFFF1A4CC0F2C04E064B851AC0D69D879968A34BC0A8EE58D359141BC05457D86AB9BC4BC07E28F423A1A91EC06FE4A3A050344CC0C9FAE956921A1EC0F22A53CFFF1A4CC0F2C04E064B851AC0', 651, 651, 2875, -7.16790000000000038, -55.797699999999999, 'S 07 10 04', 'O 55 47 51', 168, 108);
INSERT INTO bdc.mux_grid VALUES ('168/109', '0106000020E61000000100000001030000000100000005000000E6A5A38C53344CC0F2C722D88E1A1EC0826CA21DBFBC4BC0C85AE8529AA91EC0C3BED8AE21D64BC05AB23835651F21C027F8D91DB64D4CC0EDE8D577DFD720C0E6A5A38C53344CC0F2C722D88E1A1EC0', 652, 652, 2878, -8.06359999999999921, -55.9958999999999989, 'S 08 03 49', 'O 55 59 45', 168, 109);
INSERT INTO bdc.mux_grid VALUES ('168/110', '0106000020E610000001000000010300000001000000050000005D2D1A6DB94D4CC0C125157DDDD720C07614681F28D64BC00AA5315B611F21C03E3C04B49EEF4BC0408DA360ECE922C02555B60130674CC0F70D878268A222C05D2D1A6DB94D4CC0C125157DDDD720C0', 653, 653, 2879, -8.95919999999999916, -56.1946000000000012, 'S 08 57 33', 'O 56 11 40', 168, 110);
INSERT INTO bdc.mux_grid VALUES ('168/111', '0106000020E6100000010000000103000000010000000500000080C5D4B533674CC051A4714B66A222C0DDA07FE5A5EF4BC077C93813E8E922C0281919CB32094CC0D58D85A764B424C0CB3D6E9BC0804CC0AF68BEDFE26C24C080C5D4B533674CC051A4714B66A222C0', 654, 654, 2880, -9.85479999999999912, -56.3941000000000017, 'S 09 51 17', 'O 56 23 38', 168, 111);
INSERT INTO bdc.mux_grid VALUES ('168/112', '0106000020E61000000100000001030000000100000005000000700C3DB6C4804CC0E28A3D6BE06C24C0C7D00BC13A094CC0776D98E45FB424C020088E50E0224CC03173B79BCC7E26C0C843BF456A9A4CC09D905C224D3726C0700C3DB6C4804CC0E28A3D6BE06C24C0', 655, 655, 2881, -10.7501999999999995, -56.5942000000000007, 'S 10 45 00', 'O 56 35 39', 168, 112);
INSERT INTO bdc.mux_grid VALUES ('168/113', '0106000020E61000000100000001030000000100000005000000A4E346C96E9A4CC0EEF4386F4A3726C0768FEB0EE9224CC011FAEA60C77E26C04ED3DEADA93C4CC0A84D6CCD224928C07D273A682FB44CC08648BADBA50128C0A4E346C96E9A4CC0EEF4386F4A3726C0', 656, 656, 2883, -11.6454000000000004, -56.7952000000000012, 'S 11 38 43', 'O 56 47 42', 168, 113);
INSERT INTO bdc.mux_grid VALUES ('168/114', '0106000020E610000001000000010300000001000000050000006D8BBB5634B44CC01CDA9AE8A20128C0DC1C0739B33C4CC06DA022181D4928C0143FE75A91564CC044F4F8CA65132AC0A4AD9B7812CE4CC0F32D719BEBCB29C06D8BBB5634B44CC01CDA9AE8A20128C0', 657, 657, 2884, -12.5404999999999998, -56.9971000000000032, 'S 12 32 25', 'O 56 59 49', 168, 114);
INSERT INTO bdc.mux_grid VALUES ('168/115', '0106000020E6100000010000000103000000010000000500000057BE92D417CE4CC02694D966E8CB29C0C96FABB79B564CC0368350985F132AC0F7C44DDF99704CC071F2952094DD2BC0831335FC15E84CC060031FEF1C962BC057BE92D417CE4CC02694D966E8CB29C0', 658, 658, 2885, -13.4354999999999993, -57.1998999999999995, 'S 13 26 07', 'O 57 11 59', 168, 115);
INSERT INTO bdc.mux_grid VALUES ('168/116', '0106000020E61000000100000001030000000100000005000000016B5BC81BE84CC04FFF6D7719962BC0F279F512A5704CC02052666D8DDD2BC0C9EAFFD3C58A4CC00A481B58ACA72DC0D8DB65893C024DC03AF5226238602DC0016B5BC81BE84CC04FFF6D7719962BC0', 659, 659, 2886, -14.3302999999999994, -57.4037999999999968, 'S 14 19 49', 'O 57 24 13', 168, 116);
INSERT INTO bdc.mux_grid VALUES ('168/117', '0106000020E61000000100000001030000000100000005000000B3D0B5C842024DC0B88F90A534602DC01C134FE4D18A4CC070B1F120A5A72DC04D1DC2E417A54CC03663B5F8AC712FC0E3DA28C9881C4DC07E41547D3C2A2FC0B3D0B5C842024DC0B88F90A534602DC0', 660, 660, 2887, -15.2249999999999996, -57.6086999999999989, 'S 15 13 29', 'O 57 36 31', 168, 117);
INSERT INTO bdc.mux_grid VALUES ('168/118', '0106000020E61000000100000001030000000100000005000000A7DBE07E8F1C4DC010C9EF79382A2FC0B16FFFD724A54CC0A2D6D039A5712FC0E216D5D192BF4CC0C1534943CA9D30C0D882B678FD364DC0FACC58E3137A30C0A7DBE07E8F1C4DC010C9EF79382A2FC0', 661, 661, 2890, -16.1193999999999988, -57.8149000000000015, 'S 16 07 09', 'O 57 48 53', 168, 118);
INSERT INTO bdc.mux_grid VALUES ('168/119', '0106000020E61000000100000001030000000100000005000000B2CB5CA804374DC066B52FBD117A30C09C34D1AEA0BF4CC0F4D3EF1DC69D30C0520DB37139DA4CC0A06044C1B08231C068A43E6B9D514DC012428460FC5E31C0B2CB5CA804374DC066B52FBD117A30C0', 662, 662, 2891, -17.0137, -58.0223999999999975, 'S 17 00 49', 'O 58 01 20', 168, 119);
INSERT INTO bdc.mux_grid VALUES ('168/120', '0106000020E610000001000000010300000001000000050000006256A518A5514DC0E3CABF14FA5E31C0BD5AD03F48DA4CC07551CE53AC8231C07D07E7B20EF54CC06C7FD834896732C02303BC8B6B6C4DC0DAF8C9F5D64332C06256A518A5514DC0E3CABF14FA5E31C0', 663, 663, 2892, -17.9076999999999984, -58.2312000000000012, 'S 17 54 27', 'O 58 13 52', 168, 120);
INSERT INTO bdc.mux_grid VALUES ('168/121', '0106000020E6100000010000000103000000010000000500000051A205BB736C4DC07F932D83D44332C0B64F227A1EF54CC03C5EE27C846732C0FEFC009E15104DC00A6C7DDA524C33C0984FE4DE6A874DC04DA1C8E0A22833C051A205BB736C4DC07F932D83D44332C0', 664, 664, 2894, -18.8016000000000005, -58.4414999999999978, 'S 18 48 05', 'O 58 26 29', 168, 121);
INSERT INTO bdc.mux_grid VALUES ('168/122', '0106000020E61000000100000001030000000100000005000000BBB5889473874DC0223AFE45A02833C088EAFA6626104DC05CB472D54D4C33C0FC8FA957512B4DC0FDDE59EC0C3134C0305B37859EA24DC0C464E55C5F0D34C0BBB5889473874DC0223AFE45A02833C0', 665, 665, 2895, -19.6951000000000001, -58.6533000000000015, 'S 19 41 42', 'O 58 39 11', 168, 122);
INSERT INTO bdc.mux_grid VALUES ('168/123', '0106000020E61000000100000001030000000100000005000000202409C6A7A24DC0C9C37B985C0D34C0A917B12B632B4DC0E0EC7197073134C02A85D822C5464DC0698E01A2B61535C0A39130BD09BE4DC051650BA30BF234C0202409C6A7A24DC0C9C37B985C0D34C0', 666, 666, 2896, -20.5884999999999998, -58.8667999999999978, 'S 20 35 18', 'O 58 52 00', 168, 123);
INSERT INTO bdc.mux_grid VALUES ('168/124', '0106000020E61000000100000001030000000100000005000000D910638E13BE4DC0006674B308F234C0784EF60BD8464DC026353CFAB01535C09C56316374624DC095CB2C304FFA35C0FE189EE5AFD94DC06FFC64E9A6D635C0D910638E13BE4DC0006674B308F234C0', 667, 667, 2897, -21.4816000000000003, -59.082099999999997, 'S 21 28 53', 'O 59 04 55', 168, 124);
INSERT INTO bdc.mux_grid VALUES ('168/125', '0106000020E6100000010000000103000000010000000500000053E3CB4CBAD94DC02A99F3CCA3D635C08642346C88624DC0AC964E3249FA35C0F7A2899F627E4DC0151869C8D5DE36C0C543218094F54DC0921A0E6330BB36C053E3CB4CBAD94DC02A99F3CCA3D635C0', 668, 668, 2899, -22.3744000000000014, -59.299199999999999, 'S 22 22 27', 'O 59 17 57', 168, 125);
INSERT INTO bdc.mux_grid VALUES ('168/126', '0106000020E61000000100000001030000000100000005000000155D53839FF54DC01247F4172DBB36C06D8714D4777E4DC0DC2FF770CFDE36C0148D9D84939A4DC08911C29849C337C0BC62DC33BB114EC0BE28BF3FA79F37C0155D53839FF54DC01247F4172DBB36C0', 669, 669, 2901, -23.2669999999999995, -59.5183000000000035, 'S 23 16 01', 'O 59 31 05', 168, 126);
INSERT INTO bdc.mux_grid VALUES ('168/127', '0106000020E61000000100000001030000000100000005000000BF1B92D9C6114EC0D2770BC4A39F37C0234436F1A99A4DC050BAFDE342C337C0A58DF6E70AB74DC0B3F961CBA9A738C0436552D0272E4EC037B76FAB0A8438C0BF1B92D9C6114EC0D2770BC4A39F37C0', 670, 670, 2902, -24.1593000000000018, -59.7394000000000034, 'S 24 09 33', 'O 59 44 22', 168, 127);
INSERT INTO bdc.mux_grid VALUES ('168/128', '0106000020E61000000100000001030000000100000005000000E4018A1F342E4EC092C40AFD068438C0727C169A22B74DC06BA243B5A2A738C097B109CBCCD34DC0C5122986F58B39C008377D50DE4A4EC0EB34F0CD596839C0E4018A1F342E4EC092C40AFD068438C0', 671, 671, 2904, -25.0512000000000015, -59.9628000000000014, 'S 25 03 04', 'O 59 57 46', 168, 128);
INSERT INTO bdc.mux_grid VALUES ('168/129', '0106000020E61000000100000001030000000100000005000000576BBD50EB4A4EC0BECE99EA556839C034EB2FD1E5D34DC093E85A0AEE8B39C0A1BF925EDDF04DC0F4EF3AEA2B703AC0C63F20DEE2674EC01FD679CA934C3AC0576BBD50EB4A4EC0BECE99EA556839C0', 672, 672, 2905, -25.9429000000000016, -60.1884999999999977, 'S 25 56 34', 'O 60 11 18', 168, 129);
INSERT INTO bdc.mux_grid VALUES ('168/130', '0106000020E610000001000000010300000001000000050000004B9E8297F0674EC085DEC5AF8F4C3AC025F057C8F7F04DC040E9120424703AC053583206410E4EC01EBF80134C543BC079065DD539854EC063B433BFB7303BC04B9E8297F0674EC085DEC5AF8F4C3AC0', 673, 673, 2906, -26.8341999999999992, -60.4166999999999987, 'S 26 50 03', 'O 60 25 00', 168, 130);
INSERT INTO bdc.mux_grid VALUES ('168/131', '0106000020E61000000100000001030000000100000005000000A777995048854EC077B3866AB3303BC0A3A35EE45C0E4EC02F11FABD43543BC0DEC7555CFC2B4EC0A5891F1855383CC0E29B90C8E7A24EC0EE2BACC4C4143CC0A777995048854EC077B3866AB3303BC0', 674, 674, 2907, -27.7251000000000012, -60.6475000000000009, 'S 27 43 30', 'O 60 38 50', 168, 131);
INSERT INTO bdc.mux_grid VALUES ('168/132', '0106000020E61000000100000001030000000100000005000000DFF9090FF7A24EC0928A3733C0143CC074DBF8C0192C4EC0F075D34D4C383CC008087036144A4EC0D72AE107461C3DC072268184F1C04EC0783F45EDB9F83CC0DFF9090FF7A24EC0928A3733C0143CC0', 675, 675, 2909, -28.6157000000000004, -60.8810000000000002, 'S 28 36 56', 'O 60 52 51', 168, 132);
INSERT INTO bdc.mux_grid VALUES ('168/133', '0106000020E61000000100000001030000000100000005000000202153A001C14EC0D81F031CB5F83CC0688FFB34334A4EC0A715FFC23C1C3DC06E338CA98D684EC003BB8EEB1D003EC025C5E3145CDF4EC033C5924496DC3DC0202153A001C14EC0D81F031CB5F83CC0', 676, 676, 2910, -29.5060000000000002, -61.1173000000000002, 'S 29 30 21', 'O 61 07 02', 168, 133);
INSERT INTO bdc.mux_grid VALUES ('168/134', '0106000020E610000001000000010300000001000000050000003C2FF2106DDF4EC0526F413091DC3DC0EDFFF056AE684EC06173D32514003EC0ABB2420F6E874EC0F9EC3AC4DBE33EC0FEE143C92CFE4EC0EAE8A8CE58C03EC03C2FF2106DDF4EC0526F413091DC3DC0', 677, 677, 2911, -30.3958000000000013, -61.3567999999999998, 'S 30 23 44', 'O 61 21 24', 168, 134);
INSERT INTO bdc.mux_grid VALUES ('168/135', '0106000020E610000001000000010300000001000000050000001E934BB13EFE4EC019BEC57353C03EC082DA108290874EC07411E776D1E33EC080691B0BBBA64EC0A5CA7A8A7EC73FC01B22563A691D4FC04A77598700A43FC01E934BB13EFE4EC019BEC57353C03EC0', 678, 678, 2914, -31.2852999999999994, -61.5994000000000028, 'S 31 17 06', 'O 61 35 57', 168, 135);
INSERT INTO bdc.mux_grid VALUES ('168/136', '0106000020E610000001000000010300000001000000050000002798FF1A7C1D4FC0DC5F1BE2FAA33FC0E5B9A55BDFA64EC0AF2F48AE73C73FC0F76868907AC64EC03678C596825540C03C47C24F173D4FC04C10AF30C64340C02798FF1A7C1D4FC0DC5F1BE2FAA33FC0', 679, 679, 2915, -32.1743000000000023, -61.8455000000000013, 'S 32 10 27', 'O 61 50 43', 168, 136);
INSERT INTO bdc.mux_grid VALUES ('168/137', '0106000020E61000000100000001030000000100000005000000AF41B6362B3D4FC01EB1D736C34340C0C888EBD8A0C64EC01C7650DD7C5540C0CF01A6E8B2E64EC02AA12F4937C740C0B7BA70463D5D4FC02ADCB6A27DB540C0AF41B6362B3D4FC01EB1D736C34340C0', 680, 680, 2916, -33.0628999999999991, -62.0951000000000022, 'S 33 03 46', 'O 62 05 42', 168, 137);
INSERT INTO bdc.mux_grid VALUES ('168/138', '0106000020E61000000100000001030000000100000005000000D4036F42525D4FC0D092727F7AB540C035B97345DBE64EC0AADD224031C740C008A96EBA6A074FC01C6A4DC9DC3841C0A9F369B7E17D4FC0421F9D08262741C0D4036F42525D4FC0D092727F7AB540C0', 681, 681, 2917, -33.9510000000000005, -62.3485000000000014, 'S 33 57 03', 'O 62 20 54', 168, 138);
INSERT INTO bdc.mux_grid VALUES ('168/139', '0106000020E610000001000000010300000001000000050000000EA162D8F77D4FC0DAD489B9222741C0D5C51D4A95074FC052F7156CD63841C0AED61211A9284FC008B5B67D72AA41C0E6B1579F0B9F4FC092922ACBBE9841C00EA162D8F77D4FC0DAD489B9222741C0', 682, 682, 2918, -34.8387000000000029, -62.6058999999999983, 'S 34 50 19', 'O 62 36 21', 168, 139);
INSERT INTO bdc.mux_grid VALUES ('168/140', '0106000020E610000001000000010300000001000000050000007B2587F6229F4FC01680B44DBB9841C02043B4F4D5284FC0B2D362C76BAA41C01A18E764754A4FC088D829C6F71B42C077FAB966C2C04FC0EC847B4C470A42C07B2587F6229F4FC01680B44DBB9841C0', 683, 683, 2919, -35.7257999999999996, -62.8674999999999997, 'S 35 43 33', 'O 62 52 02', 168, 140);
INSERT INTO bdc.mux_grid VALUES ('168/141', '0106000020E6100000010000000103000000010000000500000065FFC706DBC04FC0308CD89D430A42C09CBB40C0A44A4FC0402A60B1F01B42C06EC75CA4D76C4FC00479DBFA6B8D42C0390BE4EA0DE34FC0F4DA53E7BE7B42C065FFC706DBC04FC0308CD89D430A42C0', 684, 684, 2920, -36.6124999999999972, -63.133499999999998, 'S 36 36 45', 'O 63 08 00', 168, 141);
INSERT INTO bdc.mux_grid VALUES ('168/142', '0106000020E610000001000000010300000001000000050000006E6906E827E34FC0205B7E04BB7B42C08BF52A9E096D4FC07E37D181648D42C0DC8AFC3DD88F4FC01A39B46BCEFE42C061FFEB43FB0250C0BA5C61EE24ED42C06E6906E827E34FC0205B7E04BB7B42C0', 685, 685, 2922, -37.4986000000000033, -63.404200000000003, 'S 37 29 55', 'O 63 24 15', 168, 142);
INSERT INTO bdc.mux_grid VALUES ('168/143', '0106000020E61000000100000001030000000100000005000000F682FCFB080350C0DC6E12D420ED42C01CCB3A000D904FC026542288C6FE42C074B25C2B80B34FC0283C7A5F1E7043C0A2768D91C21450C0DC566AAB785E43C0F682FCFB080350C0DC6E12D420ED42C0', 686, 686, 2923, -38.3841999999999999, -63.6799000000000035, 'S 38 23 03', 'O 63 40 47', 168, 143);
INSERT INTO bdc.mux_grid VALUES ('168/144', '0106000020E610000001000000010300000001000000050000000433020FD11450C022621356745E43C019D196E3B7B34FC0903A910A167043C0ACF930FDD8D74FC0FC0AE4125BE143C04E47CF9BE12650C08E32665EB9CF43C00433020FD11450C022621356745E43C0', 687, 687, 2926, -39.2691999999999979, -63.960799999999999, 'S 39 16 09', 'O 63 57 38', 168, 144);
INSERT INTO bdc.mux_grid VALUES ('168/145', '0106000020E6100000010000000103000000010000000500000006DC94EBF02650C03EBF29CAB4CF43C02677DDDC13D84FC0BB843E4552E143C00E2F95E8ECFC4FC0822F92B7835244C0FAB770715D3950C0066A7D3CE64044C006DC94EBF02650C03EBF29CAB4CF43C0', 688, 688, 2927, -40.1535999999999973, -64.2472000000000065, 'S 40 09 13', 'O 64 14 49', 168, 145);
INSERT INTO bdc.mux_grid VALUES ('168/148', '0106000020E610000001000000010300000001000000050000009A349F9C935F50C0825E1FA6FB2245C0E4C5200EDC2450C04ED2DAF18A3445C03C65351C7E3850C0D22D757E7CA545C0F2D3B3AA357350C006BAB932ED9345C09A349F9C935F50C0825E1FA6FB2245C0', 689, 689, 2931, -42.8029999999999973, -65.1430000000000007, 'S 42 48 10', 'O 65 08 34', 168, 148);
INSERT INTO bdc.mux_grid VALUES ('168/149', '0106000020E610000001000000010300000001000000050000002CE287DD487350C05E16E974E79345C01ECDD700A33850C02CB0F87571A545C092524ECCB84C50C040BC47D04B1646C09E67FEA85E8750C0722238CFC10446C02CE287DD487350C05E16E974E79345C0', 690, 690, 2932, -43.6848000000000027, -65.4549999999999983, 'S 43 41 05', 'O 65 27 18', 168, 149);
INSERT INTO bdc.mux_grid VALUES ('168/150', '0106000020E61000000100000001030000000100000005000000A4765C02738750C0FAFA51B9BB0446C0FE647EE5DF4C50C03BCCF51E401646C02EE1F07C706150C02DD1C238028746C0D2F2CE99039C50C0ECFF1ED37D7546C0A4765C02738750C0FAFA51B9BB0446C0', 691, 691, 2934, -44.565800000000003, -65.7744, 'S 44 33 56', 'O 65 46 27', 168, 150);
INSERT INTO bdc.mux_grid VALUES ('168/153', '0106000020E610000001000000010300000001000000050000000D3DA4F6F8C650C0B0606014A05647C0BE0F5C3CA58C50C0E0A85685116847C03CA9A427D6A250C084EB4CBF83D847C08AD6ECE129DD50C054A3564E12C747C00D3DA4F6F8C650C0B0606014A05647C0', 692, 692, 2938, -47.2040999999999968, -66.7815999999999974, 'S 47 12 14', 'O 66 46 53', 168, 153);
INSERT INTO bdc.mux_grid VALUES ('168/154', '0106000020E61000000100000001030000000100000005000000DEFAD4C543DD50C0C00437900AC747C0089FA0DC07A350C0AA43CDE174D847C03096B2AFD5B950C0FC9116CEC94848C006F2E69811F450C01453807C5F3748C0DEFAD4C543DD50C0C00437900AC747C0', 693, 693, 2940, -48.0818000000000012, -67.1354000000000042, 'S 48 04 54', 'O 67 08 07', 168, 154);
INSERT INTO bdc.mux_grid VALUES ('168/155', '0106000020E610000001000000010300000001000000050000002460FE272DF450C0AC04A03E573748C05EC376950ABA50C0662D53FCB94848C012CCF79E7FD150C068BC4B16F0B848C0D8687F31A20B51C0AE9398588DA748C02460FE272DF450C0AC04A03E573748C0', 694, 694, 2941, -48.9585000000000008, -67.4993000000000052, 'S 48 57 30', 'O 67 29 57', 168, 155);
INSERT INTO bdc.mux_grid VALUES ('168/156', '0106000020E61000000100000001030000000100000005000000F6B0D78EBF0B51C045C77A9084A748C0EE4A00F8B7D150C0EE9E623CDFB848C0A0BA8963DFE950C0068C3FDFF42849C0A82061FAE62351C05AB457339A1749C0F6B0D78EBF0B51C045C77A9084A748C0', 695, 695, 2942, -49.8342999999999989, -67.8739000000000061, 'S 49 50 03', 'O 67 52 25', 168, 156);
INSERT INTO bdc.mux_grid VALUES ('168/94', '0106000020E61000000100000001030000000100000005000000A4DD834F1EBB4AC065698975FAA717400E22589683434AC0B442A374E718174097B7B3F8BD5C4AC0C289A4D0818313402D73DFB158D44AC070B08AD194121440A4DD834F1EBB4AC065698975FAA71740', 696, 696, 2969, 5.37619999999999987, -53.0482000000000014, 'N 05 22 34', 'O 53 02 53', 168, 94);
INSERT INTO bdc.mux_grid VALUES ('168/95', '0106000020E61000000100000001030000000100000005000000E621827256D44AC04E28462192121440C3404ECFB95C4AC0EB4C2FD67C831340DCFF60F5E7754AC035E6AA3B0EDC0F40FEE0949884ED4AC07D4EEC681C7D1040E621827256D44AC04E28462192121440', 697, 697, 2970, 4.48029999999999973, -53.2449999999999974, 'N 04 28 49', 'O 53 14 42', 168, 95);
INSERT INTO bdc.mux_grid VALUES ('168/96', '0106000020E610000001000000010300000001000000050000005A5401B982ED4AC0886C3D2B1A7D1040E7DB4F82E4754AC07490F7FA05DC0F40CBC56595088F4AC0F4993A0400B108403D3E17CCA6064BC092E2BD5F2ECF09405A5401B982ED4AC0886C3D2B1A7D1040', 698, 698, 2971, 3.58429999999999982, -53.4414999999999978, 'N 03 35 03', 'O 53 26 29', 168, 96);
INSERT INTO bdc.mux_grid VALUES ('168/97', '0106000020E610000001000000010300000001000000050000007F93674BA5064BC0186D65C72ACF0940426A01D7058F4AC05D1AC973F9B008409F6271FB21A84AC099641597DE850140DD8BD76FC11F4BC054B7B1EA0FA402407F93674BA5064BC0186D65C72ACF0940', 699, 699, 2973, 2.68829999999999991, -53.6377000000000024, 'N 02 41 17', 'O 53 38 15', 168, 97);
INSERT INTO bdc.mux_grid VALUES ('168/98', '0106000020E6100000010000000103000000010000000500000029F5534DC01F4BC0F0D1A6330DA4024065F869F01FA84AC05A3FC2B3D98501404BF5A64636C14AC05212141E5FB5F43F0FF290A3D6384BC07C37DD1DC6F1F63F29F5534DC01F4BC0F0D1A6330DA40240', 700, 700, 2974, 1.79220000000000002, -53.8337999999999965, 'N 01 47 31', 'O 53 50 01', 168, 98);
INSERT INTO bdc.mux_grid VALUES ('168/99', '0106000020E6100000010000000103000000010000000500000049F9AEDED5384BC02206CC6FC2F1F63F500103EE34C14AC0EEBD00AD58B5F43F6936A99347DA4AC05B3A4E30C47BD93F622E5584E8514BC08DADBD9DB536E13F49F9AEDED5384BC02206CC6FC2F1F63F', 701, 701, 2975, 0.896100000000000008, -54.0296999999999983, 'N 00 53 45', 'O 54 01 46', 168, 99);
INSERT INTO bdc.mux_grid VALUES ('169/100', '0106000020E61000000100000001030000000100000005000000CC8E5C1072CD4BC0B80D24BEB136E13F2E036AE0D0554BC0A0AC07B6B77BD93F982049F1E16E4BC04A59525307DEDFBF36AC3B2183E64BC07AEA118D5BECD6BFCC8E5C1072CD4BC0B80D24BEB136E13F', 702, 702, 2976, 0, -55.1906999999999996, 'N 00 00 00', 'O 55 11 26', 169, 100);
INSERT INTO bdc.mux_grid VALUES ('169/101', '0106000020E610000001000000010300000001000000050000000954B01683E64BC0A775E2565CECD6BFC478D4FBE16E4BC02ACE818906DEDFBFEE10F892F3874BC0B4FDAB51EE4DF6BF33ECD3AD94FF4BC0932704C58311F4BF0954B01683E64BC0A775E2565CECD6BF', 703, 703, 2979, -0.896100000000000008, -55.3864999999999981, 'S 00 53 45', 'O 55 23 11', 169, 101);
INSERT INTO bdc.mux_grid VALUES ('169/102', '0106000020E610000001000000010300000001000000050000006C38560095FF4BC0D0BC373A8211F4BF7A5CF84EF4874BC052261ACEEA4DF6BF2281AF8708A14BC0305B579B245202C0145D0D39A9184CC06F266651F03301C06C38560095FF4BC0D0BC373A8211F4BF', 704, 704, 2980, -1.79220000000000002, -55.5823999999999998, 'S 01 47 31', 'O 55 34 56', 169, 102);
INSERT INTO bdc.mux_grid VALUES ('169/103', '0106000020E61000000100000001030000000100000005000000E175C4E8A9184CC0E0FB01ADEE3301C0182C7EF509A14BC0F3A42930215202C0225163EC22BA4BC07FF73AA7437D09C0EB9AA9DFC2314CC06B4E1324115F08C0E175C4E8A9184CC0E0FB01ADEE3301C0', 705, 705, 2981, -2.68829999999999991, -55.7783999999999978, 'S 02 41 17', 'O 55 46 42', 169, 103);
INSERT INTO bdc.mux_grid VALUES ('169/104', '0106000020E610000001000000010300000001000000050000008C03E9ECC3314CC0B061E99F0E5F08C02F8EAE0C25BA4BC0D5B307913E7D09C0BCC1B0E044D34BC0D0F04658275410C01937EBC0E34A4CC0798F6FBF1E8A0FC08C03E9ECC3314CC0B061E99F0E5F08C0', 706, 706, 2983, -3.58429999999999982, -55.9746999999999986, 'S 03 35 03', 'O 55 58 28', 169, 104);
INSERT INTO bdc.mux_grid VALUES ('169/105', '0106000020E61000000100000001030000000100000005000000CF23332CE54A4CC08D274D5A1B8A0FC0763B7CB447D34BC075E973F6235410C070C4EA8770EC4BC00CBDD50CA0E913C0C9ACA1FF0D644CC05F6788C3895A13C0CF23332CE54A4CC08D274D5A1B8A0FC0', 707, 707, 2984, -4.48029999999999973, -56.1711999999999989, 'S 04 28 49', 'O 56 10 16', 169, 105);
INSERT INTO bdc.mux_grid VALUES ('169/106', '0106000020E6100000010000000103000000010000000500000060869FC90F644CC0D485AB9F875A13C06DA6901074EC4BC0D736ABD29BE913C0E21F2A0AA8054CC0F7E66221097F17C0D5FF38C3437D4CC0F63563EEF4EF16C060869FC90F644CC0D485AB9F875A13C0', 708, 708, 2985, -5.37619999999999987, -56.3680000000000021, 'S 05 22 34', 'O 56 22 04', 169, 106);
INSERT INTO bdc.mux_grid VALUES ('169/107', '0106000020E61000000100000001030000000100000005000000EC16C8EC457D4CC00C4D3458F2EF16C0D7785C49AC054CC07CA6D90C047F17C04C856295ED1E4CC0495CB3C45F141BC05F23CE3887964CC0D9020E104E851AC0EC16C8EC457D4CC00C4D3458F2EF16C0', 709, 709, 2986, -6.27210000000000001, -56.5651999999999973, 'S 06 16 19', 'O 56 33 54', 169, 107);
INSERT INTO bdc.mux_grid VALUES ('169/108', '0106000020E610000001000000010300000001000000050000009E92F8C289964CC03FC04E064B851AC070052D8DF21E4CC009EE58D359141BC0EEBE7D5E43384CC0DF27F423A1A91EC01C4C4994DAAF4CC014FAE956921A1EC09E92F8C289964CC03FC04E064B851AC0', 710, 710, 2987, -7.16790000000000038, -56.7627999999999986, 'S 07 10 04', 'O 56 45 46', 169, 108);
INSERT INTO bdc.mux_grid VALUES ('169/109', '0106000020E61000000100000001030000000100000005000000860D4980DDAF4CC04DC722D88E1A1EC020D4471149384CC0255AE8529AA91EC064267EA2AB514CC048B23835651F21C0C95F7F1140C94CC0DBE8D577DFD720C0860D4980DDAF4CC04DC722D88E1A1EC0', 711, 711, 2990, -8.06359999999999921, -56.9609999999999985, 'S 08 03 49', 'O 56 57 39', 169, 109);
INSERT INTO bdc.mux_grid VALUES ('169/110', '0106000020E610000001000000010300000001000000050000001195BF6043C94CC0A425157DDDD720C0077C0D13B2514CC002A5315B611F21C0D2A3A9A7286B4CC07A8DA360ECE922C0DCBC5BF5B9E24CC01B0E878268A222C01195BF6043C94CC0A425157DDDD720C0', 712, 712, 2991, -8.95919999999999916, -57.1597999999999971, 'S 08 57 33', 'O 57 09 35', 169, 110);
INSERT INTO bdc.mux_grid VALUES ('169/111', '0106000020E61000000100000001030000000100000005000000112D7AA9BDE24CC08DA4714B66A222C0B20825D92F6B4CC089C93813E8E922C0FD80BEBEBC844CC0E68D85A764B424C05CA5138F4AFC4CC0EA68BEDFE26C24C0112D7AA9BDE24CC08DA4714B66A222C0', 713, 713, 2992, -9.85479999999999912, -57.3592000000000013, 'S 09 51 17', 'O 57 21 33', 169, 111);
INSERT INTO bdc.mux_grid VALUES ('169/112', '0106000020E610000001000000010300000001000000050000001874E2A94EFC4CC0118B3D6BE06C24C06E38B1B4C4844CC0A36D98E45FB424C0C66F33446A9E4CC05E73B79BCC7E26C06EAB6439F4154DC0CB905C224D3726C01874E2A94EFC4CC0118B3D6BE06C24C0', 714, 714, 2994, -10.7501999999999995, -57.5593999999999966, 'S 10 45 00', 'O 57 33 33', 169, 112);
INSERT INTO bdc.mux_grid VALUES ('169/113', '0106000020E610000001000000010300000001000000050000004A4BECBCF8154DC01EF5386F4A3726C019F79002739E4CC03EFAEA60C77E26C0EA3A84A133B84CC0574D6CCD224928C01A8FDF5BB92F4DC03548BADBA50128C04A4BECBCF8154DC01EF5386F4A3726C0', 715, 715, 2995, -11.6454000000000004, -57.7603999999999971, 'S 11 38 43', 'O 57 45 37', 169, 113);
INSERT INTO bdc.mux_grid VALUES ('169/114', '0106000020E6100000010000000103000000010000000500000018F3604ABE2F4DC0C2D99AE8A20128C06684AC2C3DB84CC026A022181D4928C0A4A68C4E1BD24CC07EF4F8CA65132AC05815416C9C494DC0192E719BEBCB29C018F3604ABE2F4DC0C2D99AE8A20128C0', 716, 716, 2996, -12.5404999999999998, -57.9622000000000028, 'S 12 32 25', 'O 57 57 44', 169, 114);
INSERT INTO bdc.mux_grid VALUES ('169/115', '0106000020E61000000100000001030000000100000005000000002638C8A1494DC05494D966E8CB29C072D750AB25D24CC0638350985F132AC0A12CF3D223EC4CC09BF2952094DD2BC02C7BDAEF9F634DC08B031FEF1C962BC0002638C8A1494DC05494D966E8CB29C0', 717, 717, 2997, -13.4354999999999993, -58.1649999999999991, 'S 13 26 07', 'O 58 09 54', 169, 115);
INSERT INTO bdc.mux_grid VALUES ('169/116', '0106000020E61000000100000001030000000100000005000000A5D200BCA5634DC081FF6D7719962BC097E19A062FEC4CC05052666D8DDD2BC06652A5C74F064DC0B9471B58ACA72DC075430B7DC67D4DC0ECF4226238602DC0A5D200BCA5634DC081FF6D7719962BC0', 718, 718, 2998, -14.3302999999999994, -58.3688999999999965, 'S 14 19 49', 'O 58 22 08', 169, 116);
INSERT INTO bdc.mux_grid VALUES ('169/117', '0106000020E610000001000000010300000001000000050000008B385BBCCC7D4DC0468F90A534602DC08D7AF4D75B064DC039B1F120A5A72DC0C48467D8A1204DC08063B5F8AC712FC0C242CEBC12984DC08D41547D3C2A2FC08B385BBCCC7D4DC0468F90A534602DC0', 719, 719, 3000, -15.2249999999999996, -58.5739000000000019, 'S 15 13 29', 'O 58 34 25', 169, 117);
INSERT INTO bdc.mux_grid VALUES ('169/118', '0106000020E610000001000000010300000001000000050000006B43867219984DC02DC9EF79382A2FC051D7A4CBAE204DC0D2D6D039A5712FC0827E7AC51C3B4DC0DB534943CA9D30C09AEA5B6C87B24DC00ACD58E3137A30C06B43867219984DC02DC9EF79382A2FC0', 720, 720, 3002, -16.1193999999999988, -58.7800000000000011, 'S 16 07 09', 'O 58 46 48', 169, 118);
INSERT INTO bdc.mux_grid VALUES ('169/119', '0106000020E610000001000000010300000001000000050000006633029C8EB24DC07BB52FBD117A30C02F9C76A22A3B4DC013D4EF1DC69D30C0E6745865C3554DC0BD6044C1B08231C01E0CE45E27CD4DC025428460FC5E31C06633029C8EB24DC07BB52FBD117A30C0', 721, 721, 3003, -17.0137, -58.9874999999999972, 'S 17 00 49', 'O 58 59 15', 169, 119);
INSERT INTO bdc.mux_grid VALUES ('169/120', '0106000020E61000000100000001030000000100000005000000E9BD4A0C2FCD4DC004CBBF14FA5E31C0ACC27533D2554DC07651CE53AC8231C05D6F8CA698704DC0EE7ED834896732C09A6A617FF5E74DC07CF8C9F5D64332C0E9BD4A0C2FCD4DC004CBBF14FA5E31C0', 722, 722, 3005, -17.9076999999999984, -59.1963000000000008, 'S 17 54 27', 'O 59 11 46', 169, 120);
INSERT INTO bdc.mux_grid VALUES ('169/121', '0106000020E61000000100000001030000000100000005000000D809ABAEFDE74DC01D932D83D44332C03EB7C76DA8704DC0D95DE27C846732C09364A6919F8B4DC0276C7DDA524C33C02CB789D2F4024EC06BA1C8E0A22833C0D809ABAEFDE74DC01D932D83D44332C0', 723, 723, 3006, -18.8016000000000005, -59.4065999999999974, 'S 18 48 05', 'O 59 24 23', 169, 121);
INSERT INTO bdc.mux_grid VALUES ('169/122', '0106000020E61000000100000001030000000100000005000000611D2E88FD024EC03A3AFE45A02833C02F52A05AB08B4DC073B472D54D4C33C0A2F74E4BDBA64DC015DF59EC0C3134C0D5C2DC78281E4EC0DB64E55C5F0D34C0611D2E88FD024EC03A3AFE45A02833C0', 724, 724, 3007, -19.6951000000000001, -59.6184999999999974, 'S 19 41 42', 'O 59 37 06', 169, 122);
INSERT INTO bdc.mux_grid VALUES ('169/123', '0106000020E61000000100000001030000000100000005000000F48BAEB9311E4EC0D3C37B985C0D34C0357F561FEDA64DC0FEEC7197073134C0B9EC7D164FC24DC0878E01A2B61535C078F9D5B093394EC05B650BA30BF234C0F48BAEB9311E4EC0D3C37B985C0D34C0', 725, 725, 3008, -20.5884999999999998, -59.8320000000000007, 'S 20 35 18', 'O 59 49 55', 169, 123);
INSERT INTO bdc.mux_grid VALUES ('169/124', '0106000020E61000000100000001030000000100000005000000AF7808829D394EC0096674B308F234C00AB69BFF61C24DC044353CFAB01535C02EBED656FEDD4DC0B3CB2C304FFA35C0D28043D939554EC078FC64E9A6D635C0AF7808829D394EC0096674B308F234C0', 726, 726, 3010, -21.4816000000000003, -60.0471999999999966, 'S 21 28 53', 'O 60 02 49', 169, 124);
INSERT INTO bdc.mux_grid VALUES ('169/125', '0106000020E61000000100000001030000000100000005000000544B714044554EC02699F3CCA3D635C0FDA9D95F12DE4DC0D1964E3249FA35C0700A2F93ECF94DC03B1869C8D5DE36C0C8ABC6731E714EC0901A0E6330BB36C0544B714044554EC02699F3CCA3D635C0', 727, 727, 3011, -22.3744000000000014, -60.2642999999999986, 'S 22 22 27', 'O 60 15 51', 169, 125);
INSERT INTO bdc.mux_grid VALUES ('169/126', '0106000020E61000000100000001030000000100000005000000E5C4F87629714EC01B47F4172DBB36C0FBEEB9C701FA4DC0FA2FF770CFDE36C094F442781D164EC02711C29849C337C080CA8127458D4EC04828BF3FA79F37C0E5C4F87629714EC01B47F4172DBB36C0', 728, 728, 3013, -23.2669999999999995, -60.4834000000000032, 'S 23 16 01', 'O 60 29 00', 169, 126);
INSERT INTO bdc.mux_grid VALUES ('169/127', '0106000020E61000000100000001030000000100000005000000428337CD508D4EC06F770BC4A39F37C0A4ABDBE433164EC0ECB9FDE342C337C028F59BDB94324EC051F961CBA9A738C0C6CCF7C3B1A94EC0D4B66FAB0A8438C0428337CD508D4EC06F770BC4A39F37C0', 729, 729, 3015, -24.1593000000000018, -60.7045999999999992, 'S 24 09 33', 'O 60 42 16', 169, 127);
INSERT INTO bdc.mux_grid VALUES ('169/128', '0106000020E610000001000000010300000001000000050000000E692F13BEA94EC04BC40AFD068438C028E4BB8DAC324EC0FAA143B5A2A738C05D19AFBE564F4EC0D2122986F58B39C0449E224468C64EC02435F0CD596839C00E692F13BEA94EC04BC40AFD068438C0', 730, 730, 3016, -25.0512000000000015, -60.9279999999999973, 'S 25 03 04', 'O 60 55 40', 169, 128);
INSERT INTO bdc.mux_grid VALUES ('169/129', '0106000020E61000000100000001030000000100000005000000DDD2624475C64EC0E0CE99EA556839C04353D5C46F4F4EC08BE85A0AEE8B39C09E273852676C4EC06DEF3AEA2B703AC03AA7C5D16CE34EC0C1D579CA934C3AC0DDD2624475C64EC0E0CE99EA556839C0', 731, 731, 3017, -25.9429000000000016, -61.1537000000000006, 'S 25 56 34', 'O 61 09 13', 169, 129);
INSERT INTO bdc.mux_grid VALUES ('169/130', '0106000020E61000000100000001030000000100000005000000D005288B7AE34EC022DEC5AF8F4C3AC0AA57FDBB816C4EC0DFE8120424703AC0D6BFD7F9CA894EC0BBBE80134C543BC0FC6D02C9C3004FC000B433BFB7303BC0D005288B7AE34EC022DEC5AF8F4C3AC0', 732, 732, 3018, -26.8341999999999992, -61.3817999999999984, 'S 26 50 03', 'O 61 22 54', 169, 130);
INSERT INTO bdc.mux_grid VALUES ('169/131', '0106000020E6100000010000000103000000010000000500000059DF3E44D2004FC006B3866AB3303BC0550B04D8E6894EC0BD10FABD43543BC0A02FFB4F86A74EC0B3891F1855383CC0A60336BC711E4FC0FC2BACC4C4143CC059DF3E44D2004FC006B3866AB3303BC0', 733, 733, 3020, -27.7251000000000012, -61.6126000000000005, 'S 27 43 30', 'O 61 36 45', 169, 131);
INSERT INTO bdc.mux_grid VALUES ('169/132', '0106000020E61000000100000001030000000100000005000000A961AF02811E4FC09F8A3733C0143CC0F7429EB4A3A74EC01176D34D4C383CC09C6F152A9EC54EC0782BE107461C3DC04B8E26787B3C4FC0054045EDB9F83CC0A961AF02811E4FC09F8A3733C0143CC0', 734, 734, 3021, -28.6157000000000004, -61.8460999999999999, 'S 28 36 56', 'O 61 50 45', 169, 132);
INSERT INTO bdc.mux_grid VALUES ('169/133', '0106000020E610000001000000010300000001000000050000000489F8938B3C4FC06220031CB5F83CC008F7A028BDC54EC04516FFC23C1C3DC0FC9A319D17E44EC021BB8EEB1D003EC0F92C8908E65A4FC03EC5924496DC3DC00489F8938B3C4FC06220031CB5F83CC0', 735, 735, 3022, -29.5060000000000002, -62.0825000000000031, 'S 29 30 21', 'O 62 04 56', 169, 133);
INSERT INTO bdc.mux_grid VALUES ('169/134', '0106000020E61000000100000001030000000100000005000000D1969704F75A4FC06D6F413091DC3DC08067964A38E44EC07C73D32514003EC0311AE802F8024FC096EC3AC4DBE33EC07F49E9BCB6794FC087E8A8CE58C03EC0D1969704F75A4FC06D6F413091DC3DC0', 736, 736, 3023, -30.3958000000000013, -62.3218999999999994, 'S 30 23 44', 'O 62 19 18', 169, 134);
INSERT INTO bdc.mux_grid VALUES ('169/135', '0106000020E6100000010000000103000000010000000500000095FAF0A4C8794FC0BABDC57353C03EC08542B6751A034FC0EC10E776D1E33EC094D1C0FE44224FC09CCA7A8A7EC73FC0A489FB2DF3984FC06B77598700A43FC095FAF0A4C8794FC0BABDC57353C03EC0', 737, 737, 3026, -31.2852999999999994, -62.5645999999999987, 'S 31 17 06', 'O 62 33 52', 169, 135);
INSERT INTO bdc.mux_grid VALUES ('169/136', '0106000020E61000000100000001030000000100000005000000BBFFA40E06994FC0F85F1BE2FAA33FC0BB214B4F69224FC0B82F48AE73C73FC0CDD00D8404424FC03A78C596825540C0CEAE6743A1B84FC05A10AF30C64340C0BBFFA40E06994FC0F85F1BE2FAA33FC0', 738, 738, 3027, -32.1743000000000023, -62.8106000000000009, 'S 32 10 27', 'O 62 48 38', 169, 136);
INSERT INTO bdc.mux_grid VALUES ('169/137', '0106000020E610000001000000010300000001000000050000005CA95B2AB5B84FC026B1D736C34340C072F090CC2A424FC0267650DD7C5540C08C694BDC3C624FC072A12F4937C740C07622163AC7D84FC074DCB6A27DB540C05CA95B2AB5B84FC026B1D736C34340C0', 739, 739, 3028, -33.0628999999999991, -63.060299999999998, 'S 33 03 46', 'O 63 03 36', 169, 137);
INSERT INTO bdc.mux_grid VALUES ('169/138', '0106000020E61000000100000001030000000100000005000000D06B1436DCD84FC01093727F7AB540C0A720193965624FC000DE224031C740C0561014AEF4824FC0F2694DC9DC3841C0815B0FAB6BF94FC0041F9D08262741C0D06B1436DCD84FC01093727F7AB540C0', 740, 740, 3030, -33.9510000000000005, -63.3136999999999972, 'S 33 57 03', 'O 63 18 49', 169, 138);
INSERT INTO bdc.mux_grid VALUES ('169/139', '0106000020E610000001000000010300000001000000050000008C0808CC81F94FC0A8D489B9222741C09C2DC33D1F834FC014F7156CD63841C0603EB80433A44FC086B4B67D72AA41C0A68C7EC94A0D50C01C922ACBBE9841C08C0808CC81F94FC0A8D489B9222741C0', 741, 741, 3031, -34.8387000000000029, -63.570999999999998, 'S 34 50 19', 'O 63 34 15', 169, 139);
INSERT INTO bdc.mux_grid VALUES ('169/140', '0106000020E6100000010000000103000000010000000500000088461675560D50C0987FB44DBB9841C075AA59E85FA44FC03DD362C76BAA41C0757F8C58FFC54FC022D829C6F71B42C006B12F2D261E50C07E847B4C470A42C088461675560D50C0987FB44DBB9841C0', 742, 742, 3032, -35.7257999999999996, -63.8325999999999993, 'S 35 43 33', 'O 63 49 57', 169, 140);
INSERT INTO bdc.mux_grid VALUES ('169/141', '0106000020E6100000010000000103000000010000000500000054B3367D321E50C0CF8BD89D430A42C05823E6B32EC64FC0CA2960B1F01B42C03F2F029861E84FC0C478DBFA6B8D42C04AB944EF4B2F50C0C8DA53E7BE7B42C054B3367D321E50C0CF8BD89D430A42C0', 743, 743, 3034, -36.6124999999999972, -64.0986000000000047, 'S 36 36 45', 'O 64 05 55', 169, 141);
INSERT INTO bdc.mux_grid VALUES ('169/142', '0106000020E61000000100000001030000000100000005000000C4E8D5ED582F50C0D65A7E04BB7B42C01D5DD09193E84FC04B37D181648D42C036F9D018B10550C0E638B46BCEFE42C06EB3BE3DC04050C0725C61EE24ED42C0C4E8D5ED582F50C0D65A7E04BB7B42C0', 744, 744, 3035, -37.4986000000000033, -64.3693999999999988, 'S 37 29 55', 'O 64 22 09', 169, 142);
INSERT INTO bdc.mux_grid VALUES ('169/143', '0106000020E610000001000000010300000001000000050000001037CFF5CD4050C08E6E12D420ED42C04619F079CB0550C0F8532288C6FE42C0080D810F851750C0763C7A5F1E7043C0D02A608B875250C00E576AAB785E43C01037CFF5CD4050C08E6E12D420ED42C0', 745, 745, 3036, -38.3841999999999999, -64.644999999999996, 'S 38 23 03', 'O 64 38 42', 169, 143);
INSERT INTO bdc.mux_grid VALUES ('169/144', '0106000020E6100000010000000103000000010000000500000014E7D408965250C05E621356745E43C02C1C9EEBA01750C0EE3A910A167043C060306B78B12950C0DC0AE4125BE143C048FBA195A66450C04D32665EB9CF43C014E7D408965250C05E621356745E43C0', 746, 746, 3038, -39.2691999999999979, -64.9258999999999986, 'S 39 16 09', 'O 64 55 33', 169, 144);
INSERT INTO bdc.mux_grid VALUES ('169/145', '0106000020E61000000100000001030000000100000005000000FE8F67E5B56450C0FCBE29CAB4CF43C0466F41E8CE2950C08A843E4552E143C03A4B1D6E3B3C50C0542F92B7835244C0F26B436B227750C0C4697D3CE64044C0FE8F67E5B56450C0FCBE29CAB4CF43C0', 747, 747, 3039, -40.1535999999999973, -65.2124000000000024, 'S 40 09 13', 'O 65 12 44', 169, 145);
INSERT INTO bdc.mux_grid VALUES ('169/146', '0106000020E61000000100000001030000000100000005000000E009699B327750C0A41A2765E14044C044D98F8C5A3C50C0A2B125697A5244C0F71AAF64284F50C0EE75EC7297C344C0904B8873008A50C0F0DEED6EFEB144C0E009699B327750C0A41A2765E14044C0', 748, 748, 3040, -41.0373999999999981, -65.5045999999999964, 'S 41 02 14', 'O 65 30 16', 169, 146);
INSERT INTO bdc.mux_grid VALUES ('169/147', '0106000020E61000000100000001030000000100000005000000FAC45D93118A50C0C673E94FF9B144C07078014F494F50C09E9DF89A8DC344C0F215DE317E6250C0B649DF5C953445C07E623A76469D50C0DE1FD011012345C0FAC45D93118A50C0C673E94FF9B144C0', 749, 749, 3041, -41.9206000000000003, -65.8031000000000006, 'S 41 55 14', 'O 65 48 11', 169, 147);
INSERT INTO bdc.mux_grid VALUES ('169/148', '0106000020E610000001000000010300000001000000050000003FE87196589D50C05A5E1FA6FB2245C0CC79F307A16250C010D2DAF18A3445C03A190816437650C0122E757E7CA545C0AC8786A4FAB050C05CBAB932ED9345C03FE87196589D50C05A5E1FA6FB2245C0', 750, 750, 3042, -42.8029999999999973, -66.1081999999999965, 'S 42 48 10', 'O 66 06 29', 169, 148);
INSERT INTO bdc.mux_grid VALUES ('169/149', '0106000020E61000000100000001030000000100000005000000F4955AD70DB150C0AE16E974E79345C0E680AAFA677650C07CB0F87571A545C0420621C67D8A50C014BC47D04B1646C0501BD1A223C550C0462238CFC10446C0F4955AD70DB150C0AE16E974E79345C0', 751, 751, 3043, -43.6848000000000027, -66.4201999999999941, 'S 43 41 05', 'O 66 25 12', 169, 149);
INSERT INTO bdc.mux_grid VALUES ('169/150', '0106000020E61000000100000001030000000100000005000000502A2FFC37C550C0CCFA51B9BB0446C0C61851DFA48A50C006CCF51E401646C0EA94C376359F50C0C4D0C238028746C074A6A193C8D950C08CFF1ED37D7546C0502A2FFC37C550C0CCFA51B9BB0446C0', 752, 752, 3044, -44.565800000000003, -66.7395999999999958, 'S 44 33 56', 'O 66 44 22', 169, 150);
INSERT INTO bdc.mux_grid VALUES ('169/151', '0106000020E61000000100000001030000000100000005000000D2545A29DED950C052359D5E777546C0629512EE5E9F50C08C152DD2F58646C0F65382E871B450C028DF338A9EF746C06413CA23F1EE50C0EEFEA31620E646C0D2545A29DED950C052359D5E777546C0', 753, 753, 3045, -45.4461000000000013, -67.0668000000000006, 'S 45 26 45', 'O 67 04 00', 169, 151);
INSERT INTO bdc.mux_grid VALUES ('169/152', '0106000020E61000000100000001030000000100000005000000668FC70D08EF50C008B05F3C19E646C0EA9177EB9DB450C0E4BDBC6091F746C0F851A3753BCA50C062539E801F6847C0754FF397A50451C08445415CA75647C0668FC70D08EF50C008B05F3C19E646C0', 754, 754, 3047, -46.3254999999999981, -67.4024000000000001, 'S 46 19 31', 'O 67 24 08', 169, 152);
INSERT INTO bdc.mux_grid VALUES ('169/153', '0106000020E6100000010000000103000000010000000500000000F176F0BD0451C0F2606014A05647C0B2C32E366ACA50C022A95685116847C02E5D77219BE050C0C6EB4CBF83D847C07C8ABFDBEE1A51C096A3564E12C747C000F176F0BD0451C0F2606014A05647C0', 755, 755, 3048, -47.2040999999999968, -67.7467999999999932, 'S 47 12 14', 'O 67 44 48', 169, 153);
INSERT INTO bdc.mux_grid VALUES ('169/154', '0106000020E61000000100000001030000000100000005000000CEAEA7BF081B51C0040537900AC747C0B25273D6CCE050C00244CDE174D847C0C24985A99AF750C0D89116CEC94848C0DCA5B992D63151C0DA52807C5F3748C0CEAEA7BF081B51C0040537900AC747C0', 756, 756, 3051, -48.0818000000000012, -68.1006, 'S 48 04 54', 'O 68 06 02', 169, 154);
INSERT INTO bdc.mux_grid VALUES ('169/155', '0106000020E61000000100000001030000000100000005000000CC13D121F23151C08004A03E573748C08E77498FCFF750C0152D53FCB94848C05C80CA98440F51C092BC4B16F0B848C09A1C522B674951C0009498588DA748C0CC13D121F23151C08004A03E573748C0', 757, 757, 3052, -48.9585000000000008, -68.464500000000001, 'S 48 57 30', 'O 68 27 52', 169, 155);
INSERT INTO bdc.mux_grid VALUES ('169/156', '0106000020E610000001000000010300000001000000050000008A64AA88844951C0A3C77A9084A748C0C6FED2F17C0F51C03A9F623CDFB848C05E6E5C5DA42751C0D48B3FDFF42849C020D433F4AB6151C03EB457339A1749C08A64AA88844951C0A3C77A9084A748C0', 758, 758, 3054, -49.8342999999999989, -68.8389999999999986, 'S 49 50 03', 'O 68 50 20', 169, 156);
INSERT INTO bdc.mux_grid VALUES ('169/157', '0106000020E61000000100000001030000000100000005000000EC6F8C46CB6151C02AEC65D5901749C000C30773E02751C054A93FE7E22849C080ACC260C64051C090AD5D4AD69849C06A594734B17A51C066F08338848749C0EC6F8C46CB6151C02AEC65D5901749C0', 759, 759, 3055, -50.7090000000000032, -69.2249999999999943, 'S 50 42 32', 'O 69 13 30', 169, 157);
INSERT INTO bdc.mux_grid VALUES ('169/158', '0106000020E610000001000000010300000001000000050000000C8983A6D27A51C004C0EA377A8749C09A662A84064151C0E220061CC39849C04EFB6F23B85A51C07E7CBB4E92084AC0C01DC945849451C0A01BA06A49F749C00C8983A6D27A51C004C0EA377A8749C0', 760, 760, 3056, -51.5825999999999993, -69.6233000000000004, 'S 51 34 57', 'O 69 37 23', 169, 158);
INSERT INTO bdc.mux_grid VALUES ('169/94', '0106000020E610000001000000010300000001000000050000004F452943A8364BC092698975FAA71740A689FD890DBF4AC0CB42A374E7181740301F59EC47D84AC0D889A4D081831340D8DA84A5E24F4BC0A0B08AD1941214404F452943A8364BC092698975FAA71740', 761, 761, 3077, 5.37619999999999987, -54.0133999999999972, 'N 05 22 34', 'O 54 00 48', 169, 94);
INSERT INTO bdc.mux_grid VALUES ('169/95', '0106000020E610000001000000010300000001000000050000009C892766E04F4BC088284621921214404DA8F3C243D84AC0F24C2FD67C831340636706E971F14AC0C0E6AA3B0EDC0F40B1483A8C0E694BC0F74EEC681C7D10409C892766E04F4BC08828462192121440', 762, 762, 3078, 4.48029999999999973, -54.2102000000000004, 'N 04 28 49', 'O 54 12 36', 169, 95);
INSERT INTO bdc.mux_grid VALUES ('169/96', '0106000020E61000000100000001030000000100000005000000FDBBA6AC0C694BC0EF6C3D2B1A7D10408343F5756EF14AC02F91F7FA05DC0F406A2D0B89920A4BC0AE993A0400B10840E4A5BCBF30824BC060E2BD5F2ECF0940FDBBA6AC0C694BC0EF6C3D2B1A7D1040', 763, 763, 3080, 3.58429999999999982, -54.4065999999999974, 'N 03 35 03', 'O 54 24 23', 169, 96);
INSERT INTO bdc.mux_grid VALUES ('169/97', '0106000020E6100000010000000103000000010000000500000021FB0C3F2F824BC0D96C65C72ACF0940EDD1A6CA8F0A4BC0321AC973F9B0084049CA16EFAB234BC0AD641597DE8501407DF37C634B9B4BC054B7B1EA0FA4024021FB0C3F2F824BC0D96C65C72ACF0940', 764, 764, 3081, 2.68829999999999991, -54.6028999999999982, 'N 02 41 17', 'O 54 36 10', 169, 97);
INSERT INTO bdc.mux_grid VALUES ('169/98', '0106000020E61000000100000001030000000100000005000000C75CF9404A9B4BC0EAD1A6330DA4024009600FE4A9234BC0613FC2B3D9850140EE5C4C3AC03C4BC06012141E5FB5F43FAD59369760B44BC07337DD1DC6F1F63FC75CF9404A9B4BC0EAD1A6330DA40240', 765, 765, 3082, 1.79220000000000002, -54.7989000000000033, 'N 01 47 31', 'O 54 47 56', 169, 98);
INSERT INTO bdc.mux_grid VALUES ('169/99', '0106000020E61000000100000001030000000100000005000000EF6054D25FB44BC03706CC6FC2F1F63FEF68A8E1BE3C4BC0E8BD00AD58B5F43F079E4E87D1554BC0373A4E30C47BD93F0896FA7772CD4BC0C2ADBD9DB536E13FEF6054D25FB44BC03706CC6FC2F1F63F', 766, 766, 3083, 0.896100000000000008, -54.9947999999999979, 'N 00 53 45', 'O 54 59 41', 169, 99);
INSERT INTO bdc.mux_grid VALUES ('170/100', '0106000020E610000001000000010300000001000000050000006FF60104FC484CC0D60D24BEB136E13FD26A0FD45AD14BC0E1AC07B6B77BD93F3E88EEE46BEA4BC05159525307DEDFBFDB13E1140D624CC096EA118D5BECD6BF6FF60104FC484CC0D60D24BEB136E13F', 767, 767, 3084, 0, -56.1557999999999993, 'N 00 00 00', 'O 56 09 20', 170, 100);
INSERT INTO bdc.mux_grid VALUES ('170/101', '0106000020E61000000100000001030000000100000005000000AEBB550A0D624CC0B275E2565CECD6BF67E079EF6BEA4BC065CE818906DEDFBF90789D867D034CC083FDAB51EE4DF6BFD85379A11E7B4CC0512704C58311F4BFAEBB550A0D624CC0B275E2565CECD6BF', 768, 768, 3086, -0.896100000000000008, -56.3515999999999977, 'S 00 53 45', 'O 56 21 05', 170, 101);
INSERT INTO bdc.mux_grid VALUES ('170/102', '0106000020E6100000010000000103000000010000000500000010A0FBF31E7B4CC09DBC373A8211F4BF21C49D427E034CC00C261ACEEA4DF6BFC8E8547B921C4CC0025B579B245202C0B7C4B22C33944CC04B266651F03301C010A0FBF31E7B4CC09DBC373A8211F4BF', 769, 769, 3087, -1.79220000000000002, -56.5476000000000028, 'S 01 47 31', 'O 56 32 51', 170, 102);
INSERT INTO bdc.mux_grid VALUES ('170/103', '0106000020E6100000010000000103000000010000000500000080DD69DC33944CC0C6FB01ADEE3301C0C59323E9931C4CC0BCA42930215202C0CFB808E0AC354CC014F83AA7437D09C08C024FD34CAD4CC01E4F1324115F08C080DD69DC33944CC0C6FB01ADEE3301C0', 770, 770, 3089, -2.68829999999999991, -56.7436000000000007, 'S 02 41 17', 'O 56 44 36', 170, 103);
INSERT INTO bdc.mux_grid VALUES ('170/104', '0106000020E610000001000000010300000001000000050000003A6B8EE04DAD4CC04A62E99F0E5F08C0D4F55300AF354CC083B407913E7D09C05D2956D4CE4E4CC0AAF04658275410C0C39E90B46DC64CC01C8F6FBF1E8A0FC03A6B8EE04DAD4CC04A62E99F0E5F08C0', 771, 771, 3090, -3.58429999999999982, -56.9397999999999982, 'S 03 35 03', 'O 56 56 23', 170, 104);
INSERT INTO bdc.mux_grid VALUES ('170/105', '0106000020E610000001000000010300000001000000050000006B8BD81F6FC64CC050274D5A1B8A0FC01BA321A8D14E4CC04CE973F6235410C0162C907BFA674CC0F0BCD50CA0E913C0661447F397DF4CC04C6788C3895A13C06B8BD81F6FC64CC050274D5A1B8A0FC0', 772, 772, 3091, -4.48029999999999973, -57.1362999999999985, 'S 04 28 49', 'O 57 08 10', 170, 105);
INSERT INTO bdc.mux_grid VALUES ('170/106', '0106000020E6100000010000000103000000010000000500000019EE44BD99DF4CC0A185AB9F875A13C0030E3604FE674CC0CC36ABD29BE913C07A87CFFD31814CC034E76221097F17C09067DEB6CDF84CC0093663EEF4EF16C019EE44BD99DF4CC0A185AB9F875A13C0', 773, 773, 3092, -5.37619999999999987, -57.3331000000000017, 'S 05 22 34', 'O 57 19 59', 170, 106);
INSERT INTO bdc.mux_grid VALUES ('170/107', '0106000020E61000000100000001030000000100000005000000837E6DE0CFF84CC0454D3458F2EF16C094E0013D36814CC08BA6D90C047F17C00AED0789779A4CC09D5CB3C45F141BC0FB8A732C11124DC056030E104E851AC0837E6DE0CFF84CC0454D3458F2EF16C0', 774, 774, 3093, -6.27210000000000001, -57.5302999999999969, 'S 06 16 19', 'O 57 31 49', 170, 107);
INSERT INTO bdc.mux_grid VALUES ('170/108', '0106000020E6100000010000000103000000010000000500000030FA9DB613124DC0C8C04E064B851AC0256DD2807C9A4CC06AEE58D359141BC0A1262352CDB34CC00328F423A1A91EC0ACB3EE87642B4DC061FAE956921A1EC030FA9DB613124DC0C8C04E064B851AC0', 775, 775, 3095, -7.16790000000000038, -57.7280000000000015, 'S 07 10 04', 'O 57 43 40', 170, 108);
INSERT INTO bdc.mux_grid VALUES ('170/109', '0106000020E610000001000000010300000001000000050000003B75EE73672B4DC06DC722D88E1A1EC0C73BED04D3B34CC05B5AE8529AA91EC0098E239635CD4CC03DB23835651F21C080C72405CA444DC0C7E8D577DFD720C03B75EE73672B4DC06DC722D88E1A1EC0', 776, 776, 3097, -8.06359999999999921, -57.9260999999999981, 'S 08 03 49', 'O 57 55 34', 170, 109);
INSERT INTO bdc.mux_grid VALUES ('170/110', '0106000020E61000000100000001030000000100000005000000C5FC6454CD444DC08F25157DDDD720C0BAE3B2063CCD4CC0ECA4315B611F21C0890B4F9BB2E64CC0868DA360ECE922C0922401E9435E4DC0290E878268A222C0C5FC6454CD444DC08F25157DDDD720C0', 777, 777, 3098, -8.95919999999999916, -58.1248999999999967, 'S 08 57 33', 'O 58 07 29', 170, 110);
INSERT INTO bdc.mux_grid VALUES ('170/111', '0106000020E61000000100000001030000000100000005000000C3941F9D475E4DC09CA4714B66A222C04170CACCB9E64CC0ACC93813E8E922C08BE863B246004DC0ED8D85A764B424C00C0DB982D4774DC0DC68BEDFE26C24C0C3941F9D475E4DC09CA4714B66A222C0', 778, 778, 3100, -9.85479999999999912, -58.3243999999999971, 'S 09 51 17', 'O 58 19 27', 170, 111);
INSERT INTO bdc.mux_grid VALUES ('170/112', '0106000020E61000000100000001030000000100000005000000BBDB879DD8774DC00A8B3D6BE06C24C013A056A84E004DC09D6D98E45FB424C069D7D837F4194DC03B73B79BCC7E26C012130A2D7E914DC0A8905C224D3726C0BBDB879DD8774DC00A8B3D6BE06C24C0', 779, 779, 3101, -10.7501999999999995, -58.5245000000000033, 'S 10 45 00', 'O 58 31 28', 170, 112);
INSERT INTO bdc.mux_grid VALUES ('170/113', '0106000020E61000000100000001030000000100000005000000E8B291B082914DC0FBF4386F4A3726C0B95E36F6FC194DC01CFAEA60C77E26C090A22995BD334DC0984D6CCD224928C0BDF6844F43AB4DC07848BADBA50128C0E8B291B082914DC0FBF4386F4A3726C0', 780, 780, 3102, -11.6454000000000004, -58.7254999999999967, 'S 11 38 43', 'O 58 43 31', 170, 113);
INSERT INTO bdc.mux_grid VALUES ('170/114', '0106000020E61000000100000001030000000100000005000000AD5A063E48AB4DC00EDA9AE8A20128C01BEC5120C7334DC05EA022181D4928C0530E3242A54D4DC015F4F8CA65132AC0E37CE65F26C54DC0C62D719BEBCB29C0AD5A063E48AB4DC00EDA9AE8A20128C0', 781, 781, 3103, -12.5404999999999998, -58.9273999999999987, 'S 12 32 25', 'O 58 55 38', 170, 114);
INSERT INTO bdc.mux_grid VALUES ('170/115', '0106000020E61000000100000001030000000100000005000000A08DDDBB2BC54DC0F393D966E8CB29C0123FF69EAF4D4DC0048350985F132AC0489498C6AD674DC09FF2952094DD2BC0D4E27FE329DF4DC08F031FEF1C962BC0A08DDDBB2BC54DC0F393D966E8CB29C0', 782, 782, 3104, -13.4354999999999993, -59.1302000000000021, 'S 13 26 07', 'O 59 07 48', 170, 115);
INSERT INTO bdc.mux_grid VALUES ('170/116', '0106000020E61000000100000001030000000100000005000000453AA6AF2FDF4DC086FF6D7719962BC0374940FAB8674DC05452666D8DDD2BC00EBA4ABBD9814DC021481B58ACA72DC01AABB07050F94DC052F5226238602DC0453AA6AF2FDF4DC086FF6D7719962BC0', 783, 783, 3106, -14.3302999999999994, -59.3340999999999994, 'S 14 19 49', 'O 59 20 02', 170, 116);
INSERT INTO bdc.mux_grid VALUES ('170/117', '0106000020E6100000010000000103000000010000000500000029A000B056F94DC0B38F90A534602DC071E299CBE5814DC07DB1F120A5A72DC09FEC0CCC2B9C4DC02463B5F8AC712FC057AA73B09C134EC05B41547D3C2A2FC029A000B056F94DC0B38F90A534602DC0', 784, 784, 3107, -15.2249999999999996, -59.5390000000000015, 'S 15 13 29', 'O 59 32 20', 170, 117);
INSERT INTO bdc.mux_grid VALUES ('170/118', '0106000020E6100000010000000103000000010000000500000004AB2B66A3134EC0F9C8EF79382A2FC00E3F4ABF389C4DC089D6D039A5712FC048E61FB9A6B64DC0F3534943CA9D30C03C520160112E4EC02ACD58E3137A30C004AB2B66A3134EC0F9C8EF79382A2FC0', 785, 785, 3109, -16.1193999999999988, -59.745199999999997, 'S 16 07 09', 'O 59 44 42', 170, 118);
INSERT INTO bdc.mux_grid VALUES ('170/119', '0106000020E61000000100000001030000000100000005000000F79AA78F182E4EC0A0B52FBD117A30C0E3031C96B4B64DC030D4EF1DC69D30C09ADCFD584DD14DC0CB6044C1B08231C0AE738952B1484EC03B428460FC5E31C0F79AA78F182E4EC0A0B52FBD117A30C0', 786, 786, 3111, -17.0137, -59.9525999999999968, 'S 17 00 49', 'O 59 57 09', 170, 119);
INSERT INTO bdc.mux_grid VALUES ('170/120', '0106000020E610000001000000010300000001000000050000006E25F0FFB8484EC01DCBBF14FA5E31C0312A1B275CD14DC09151CE53AC8231C0E1D6319A22EC4DC0F77ED834896732C01ED206737F634EC084F8C9F5D64332C06E25F0FFB8484EC01DCBBF14FA5E31C0', 787, 787, 3112, -17.9076999999999984, -60.1614999999999966, 'S 17 54 27', 'O 60 09 41', 170, 120);
INSERT INTO bdc.mux_grid VALUES ('170/121', '0106000020E610000001000000010300000001000000050000006B7150A287634EC022932D83D44332C0CF1E6D6132EC4DC0E15DE27C846732C025CC4B8529074EC01F6C7DDA524C33C0BF1E2FC67E7E4EC061A1C8E0A22833C06B7150A287634EC022932D83D44332C0', 788, 788, 3113, -18.8016000000000005, -60.3718000000000004, 'S 18 48 05', 'O 60 22 18', 170, 121);
INSERT INTO bdc.mux_grid VALUES ('170/122', '0106000020E610000001000000010300000001000000050000000285D37B877E4EC02B3AFE45A02833C0CFB9454E3A074EC066B472D54D4C33C0425FF43E65224EC0F8DE59EC0C3134C0752A826CB2994EC0BD64E55C5F0D34C00285D37B877E4EC02B3AFE45A02833C0', 789, 789, 3114, -19.6951000000000001, -60.583599999999997, 'S 19 41 42', 'O 60 35 01', 170, 122);
INSERT INTO bdc.mux_grid VALUES ('170/123', '0106000020E610000001000000010300000001000000050000007DF353ADBB994EC0BCC37B985C0D34C004E7FB1277224EC0D5EC7197073134C08654230AD93D4EC04F8E01A2B61535C0FD607BA41DB54EC036650BA30BF234C07DF353ADBB994EC0BCC37B985C0D34C0', 790, 790, 3116, -20.5884999999999998, -60.7971000000000004, 'S 20 35 18', 'O 60 47 49', 170, 123);
INSERT INTO bdc.mux_grid VALUES ('170/124', '0106000020E6100000010000000103000000010000000500000036E0AD7527B54EC0E36574B308F234C0D61D41F3EB3D4EC009353CFAB01535C0F9257C4A88594EC06BCB2C304FFA35C059E8E8CCC3D04EC044FC64E9A6D635C036E0AD7527B54EC0E36574B308F234C0', 791, 791, 3117, -21.4816000000000003, -61.0123999999999995, 'S 21 28 53', 'O 61 00 44', 170, 124);
INSERT INTO bdc.mux_grid VALUES ('170/125', '0106000020E61000000100000001030000000100000005000000C1B21634CED04EC0F898F3CCA3D635C0F5117F539C594EC07A964E3249FA35C07672D48676754EC0561869C8D5DE36C042136C67A8EC4EC0D11A0E6330BB36C0C1B21634CED04EC0F898F3CCA3D635C0', 792, 792, 3118, -22.3744000000000014, -61.2295000000000016, 'S 22 22 27', 'O 61 13 46', 170, 125);
INSERT INTO bdc.mux_grid VALUES ('170/126', '0106000020E61000000100000001030000000100000005000000792C9E6AB3EC4EC05647F4172DBB36C0D1565FBB8B754EC02230F770CFDE36C0685CE86BA7914EC04111C29849C337C01132271BCF084FC07428BF3FA79F37C0792C9E6AB3EC4EC05647F4172DBB36C0', 793, 793, 3120, -23.2669999999999995, -61.448599999999999, 'S 23 16 01', 'O 61 26 54', 170, 126);
INSERT INTO bdc.mux_grid VALUES ('170/127', '0106000020E610000001000000010300000001000000050000001CEBDCC0DA084FC085770BC4A39F37C03A1381D8BD914EC018BAFDE342C337C0CC5C41CF1EAE4EC0EDF961CBA9A738C0AE349DB73B254FC05AB76FAB0A8438C01CEBDCC0DA084FC085770BC4A39F37C0', 794, 794, 3121, -24.1593000000000018, -61.6696999999999989, 'S 24 09 33', 'O 61 40 11', 170, 127);
INSERT INTO bdc.mux_grid VALUES ('170/128', '0106000020E61000000100000001030000000100000005000000E3D0D40648254FC0D6C40AFD068438C0724B618136AE4EC0B1A243B5A2A738C0958054B2E0CA4EC0FA122986F58B39C00606C837F2414FC01F35F0CD596839C0E3D0D40648254FC0D6C40AFD068438C0', 795, 795, 3122, -25.0512000000000015, -61.8930999999999969, 'S 25 03 04', 'O 61 53 35', 170, 128);
INSERT INTO bdc.mux_grid VALUES ('170/129', '0106000020E610000001000000010300000001000000050000005E3A0838FF414FC0F2CE99EA556839C0C3BA7AB8F9CA4EC09FE85A0AEE8B39C01E8FDD45F1E74EC072EF3AEA2B703AC0BA0E6BC5F65E4FC0C5D579CA934C3AC05E3A0838FF414FC0F2CE99EA556839C0', 796, 796, 3123, -25.9429000000000016, -62.1188000000000002, 'S 25 56 34', 'O 62 07 07', 170, 129);
INSERT INTO bdc.mux_grid VALUES ('170/130', '0106000020E61000000100000001030000000100000005000000A66DCD7E045F4FC00BDEC5AF8F4C3AC03ABFA2AF0BE84EC0DCE8120424703AC065277DED54054FC0AABE80134C543BC0D0D5A7BC4D7C4FC0D8B333BFB7303BC0A66DCD7E045F4FC00BDEC5AF8F4C3AC0', 797, 797, 3124, -26.8341999999999992, -62.3470000000000013, 'S 26 50 03', 'O 62 20 49', 170, 130);
INSERT INTO bdc.mux_grid VALUES ('170/131', '0106000020E61000000100000001030000000100000005000000D046E4375C7C4FC0FBB2866AB3303BC01273A9CB70054FC09E10FABD43543BC05B97A04310234FC086891F1855383CC01A6BDBAFFB994FC0E32BACC4C4143CC0D046E4375C7C4FC0FBB2866AB3303BC0', 798, 798, 3125, -27.7251000000000012, -62.5777000000000001, 'S 27 43 30', 'O 62 34 39', 170, 131);
INSERT INTO bdc.mux_grid VALUES ('170/132', '0106000020E6100000010000000103000000010000000500000023C954F60A9A4FC0858A3733C0143CC0B9AA43A82D234FC0E275D34D4C383CC05AD7BA1D28414FC0392BE107461C3DC0C4F5CB6B05B84FC0DB3F45EDB9F83CC023C954F60A9A4FC0858A3733C0143CC0', 799, 799, 3126, -28.6157000000000004, -62.8111999999999995, 'S 28 36 56', 'O 62 48 40', 170, 132);
INSERT INTO bdc.mux_grid VALUES ('170/133', '0106000020E6100000010000000103000000010000000500000042F09D8715B84FC04920031CB5F83CC0CF5E461C47414FC00416FFC23C1C3DC0C402D790A15F4FC0D1BA8EEB1D003EC035942EFC6FD64FC015C5924496DC3DC042F09D8715B84FC04920031CB5F83CC0', 800, 800, 3127, -29.5060000000000002, -63.0476000000000028, 'S 29 30 21', 'O 63 02 51', 170, 133);
INSERT INTO bdc.mux_grid VALUES ('170/134', '0106000020E610000001000000010300000001000000050000009EFE3CF880D64FC01A6F413091DC3DC009CF3B3EC25F4FC03F73D32514003EC0C8818DF6817E4FC0CAEC3AC4DBE33EC05EB18EB040F54FC0A6E8A8CE58C03EC09EFE3CF880D64FC01A6F413091DC3DC0', 801, 801, 3129, -30.3958000000000013, -63.2871000000000024, 'S 30 23 44', 'O 63 17 13', 170, 134);
INSERT INTO bdc.mux_grid VALUES ('170/135', '0106000020E610000001000000010300000001000000050000002362969852F54FC0EEBDC57353C03EC011AA5B69A47E4FC02111E776D1E33EC01F3966F2CE9D4FC0C2CA7A8A7EC73FC09678D0903E0A50C09277598700A43FC02362969852F54FC0EEBDC57353C03EC0', 802, 802, 3131, -31.2852999999999994, -63.5296999999999983, 'S 31 17 06', 'O 63 31 47', 170, 135);
INSERT INTO bdc.mux_grid VALUES ('170/136', '0106000020E61000000100000001030000000100000005000000C8332501480A50C009601BE2FAA33FC04C89F042F39D4FC0DC2F48AE73C73FC05D38B3778EBD4FC04478C596825540C0508B869B151A50C05A10AF30C64340C0C8332501480A50C009601BE2FAA33FC0', 803, 803, 3132, -32.1743000000000023, -63.7757999999999967, 'S 32 10 27', 'O 63 46 32', 170, 136);
INSERT INTO bdc.mux_grid VALUES ('170/137', '0106000020E61000000100000001030000000100000005000000A688008F1F1A50C024B1D736C34340C01D5836C0B4BD4FC02C7650DD7C5540C046D1F0CFC6DD4FC0B0A12F4937C740C03CC5DD96282A50C0A8DCB6A27DB540C0A688008F1F1A50C024B1D736C34340C0', 804, 804, 3134, -33.0628999999999991, -64.0254000000000048, 'S 33 03 46', 'O 64 01 31', 170, 137);
INSERT INTO bdc.mux_grid VALUES ('170/138', '0106000020E61000000100000001030000000100000005000000C4E9DC14332A50C05093727F7AB540C0A088BE2CEFDD4FC034DE224031C740C04E78B9A17EFE4FC01E6A4DC9DC3841C09C615ACF7A3A50C03A1F9D08262741C0C4E9DC14332A50C05093727F7AB540C0', 805, 805, 3135, -33.9510000000000005, -64.2788000000000039, 'S 33 57 03', 'O 64 16 43', 170, 138);
INSERT INTO bdc.mux_grid VALUES ('170/139', '0106000020E6100000010000000103000000010000000500000058B8D6DF853A50C0D0D489B9222741C037956831A9FE4FC04EF7156CD63841C0F2D22E7CDE0F50C080B4B67D72AA41C0B04051C30F4B50C002922ACBBE9841C058B8D6DF853A50C0D0D489B9222741C0', 806, 806, 3136, -34.8387000000000029, -64.5361999999999938, 'S 34 50 19', 'O 64 32 10', 170, 139);
INSERT INTO bdc.mux_grid VALUES ('170/140', '0106000020E6100000010000000103000000010000000500000044FAE86E1B4B50C0967FB44DBB9841C01689FFEDF40F50C030D362C76BAA41C0A4F318A6C42050C07FD829C6F71B42C0D2640227EB5B50C0E4847B4C470A42C044FAE86E1B4B50C0967FB44DBB9841C0', 807, 807, 3137, -35.7257999999999996, -64.7977999999999952, 'S 35 43 33', 'O 64 47 51', 170, 140);
INSERT INTO bdc.mux_grid VALUES ('170/141', '0106000020E610000001000000010300000001000000050000000E670977F75B50C03A8CD89D430A42C06EC5C553DC2050C0342A60B1F01B42C058CBD3C5F53150C0F078DBFA6B8D42C0F86C17E9106D50C0F6DA53E7BE7B42C00E670977F75B50C03A8CD89D430A42C0', 808, 808, 3138, -36.6124999999999972, -65.0638000000000005, 'S 36 36 45', 'O 65 03 49', 170, 141);
INSERT INTO bdc.mux_grid VALUES ('170/142', '0106000020E61000000100000001030000000100000005000000549CA8E71D6D50C00E5B7E04BB7B42C0A8E2BAC20E3250C05837D181648D42C064ADA312764350C06A39B46BCEFE42C010679137857E50C0225D61EE24ED42C0549CA8E71D6D50C00E5B7E04BB7B42C0', 809, 809, 3139, -37.4986000000000033, -65.3345000000000056, 'S 37 29 55', 'O 65 20 04', 170, 142);
INSERT INTO bdc.mux_grid VALUES ('170/143', '0106000020E61000000100000001030000000100000005000000C0EAA1EF927E50C03A6F12D420ED42C080CDC273904350C078542288C6FE42C018C153094A5550C0F43B7A5F1E7043C058DE32854C9050C0B6566AAB785E43C0C0EAA1EF927E50C03A6F12D420ED42C0', 810, 810, 3140, -38.3841999999999999, -65.6102000000000061, 'S 38 23 03', 'O 65 36 36', 170, 143);
INSERT INTO bdc.mux_grid VALUES ('170/144', '0106000020E61000000100000001030000000100000005000000C09AA7025B9050C0FB611356745E43C01FD070E5655550C0743A910A167043C066E43D72766750C0DA0AE4125BE143C008AF748F6BA250C06032665EB9CF43C0C09AA7025B9050C0FB611356745E43C0', 811, 811, 3143, -39.2691999999999979, -65.8910999999999945, 'S 39 16 09', 'O 65 53 27', 170, 144);
INSERT INTO bdc.mux_grid VALUES ('170/145', '0106000020E61000000100000001030000000100000005000000BE433ADF7AA250C010BF29CAB4CF43C04A2314E2936750C08A843E4552E143C03EFFEF67007A50C04C2F92B7835244C0B01F1665E7B450C0D2697D3CE64044C0BE433ADF7AA250C010BF29CAB4CF43C0', 812, 812, 3144, -40.1535999999999973, -66.1774999999999949, 'S 40 09 13', 'O 66 10 39', 170, 145);
INSERT INTO bdc.mux_grid VALUES ('170/146', '0106000020E61000000100000001030000000100000005000000B8BD3B95F7B450C0AA1A2765E14044C0098D62861F7A50C0ACB125697A5244C0BACE815EED8C50C0F275EC7297C344C06AFF5A6DC5C750C0F0DEED6EFEB144C0B8BD3B95F7B450C0AA1A2765E14044C0', 813, 813, 3146, -41.0373999999999981, -66.4698000000000064, 'S 41 02 14', 'O 66 28 11', 170, 146);
INSERT INTO bdc.mux_grid VALUES ('170/147', '0106000020E610000001000000010300000001000000050000009478308DD6C750C0D673E94FF9B144C04E2CD4480E8D50C09B9DF89A8DC344C0BAC9B02B43A050C02C49DF5C953445C000160D700BDB50C0681FD011012345C09478308DD6C750C0D673E94FF9B144C0', 814, 814, 3147, -41.9206000000000003, -66.7682999999999964, 'S 41 55 14', 'O 66 46 05', 170, 147);
INSERT INTO bdc.mux_grid VALUES ('170/148', '0106000020E61000000100000001030000000100000005000000189C44901DDB50C0CD5D1FA6FB2245C0622DC60166A050C096D1DAF18A3445C0E4CCDA0F08B450C00E2E757E7CA545C09A3B599EBFEE50C045BAB932ED9345C0189C44901DDB50C0CD5D1FA6FB2245C0', 815, 815, 3148, -42.8029999999999973, -67.0733000000000033, 'S 42 48 10', 'O 67 04 23', 170, 148);
INSERT INTO bdc.mux_grid VALUES ('170/149', '0106000020E61000000100000001030000000100000005000000AA492DD1D2EE50C0A816E974E79345C09C347DF42CB450C072B0F87571A545C0F8B9F3BF42C850C004BC47D04B1646C006CFA39CE80251C0362238CFC10446C0AA492DD1D2EE50C0A816E974E79345C0', 816, 816, 3150, -43.6848000000000027, -67.3853000000000009, 'S 43 41 05', 'O 67 23 07', 170, 149);
INSERT INTO bdc.mux_grid VALUES ('170/150', '0106000020E610000001000000010300000001000000050000001EDE01F6FC0251C0B8FA51B9BB0446C078CC23D969C850C0F8CBF51E401646C0A2489670FADC50C0E4D0C238028746C0495A748D8D1751C0A4FF1ED37D7546C01EDE01F6FC0251C0B8FA51B9BB0446C0', 817, 817, 3151, -44.565800000000003, -67.7047000000000025, 'S 44 33 56', 'O 67 42 16', 170, 150);
INSERT INTO bdc.mux_grid VALUES ('170/151', '0106000020E61000000100000001030000000100000005000000A6082D23A31751C06A359D5E777546C01A49E5E723DD50C0AE152DD2F58646C0BA0755E236F250C08CDF338A9EF746C046C79C1DB62C51C048FFA31620E646C0A6082D23A31751C06A359D5E777546C0', 818, 818, 3152, -45.4461000000000013, -68.0318999999999932, 'S 45 26 45', 'O 68 01 55', 170, 151);
INSERT INTO bdc.mux_grid VALUES ('170/152', '0106000020E6100000010000000103000000010000000500000060439A07CD2C51C05AB05F3C19E646C0A1454AE562F250C04ABEBC6091F746C09405766F000851C044539E801F6847C05403C6916A4251C05445415CA75647C060439A07CD2C51C05AB05F3C19E646C0', 819, 819, 3153, -46.3254999999999981, -68.3675000000000068, 'S 46 19 31', 'O 68 22 02', 170, 152);
INSERT INTO bdc.mux_grid VALUES ('170/153', '0106000020E6100000010000000103000000010000000500000098A449EA824251C0D8606014A05647C08E7701302F0851C0F0A85685116847C00A114A1B601E51C08EEB4CBF83D847C0123E92D5B35851C076A3564E12C747C098A449EA824251C0D8606014A05647C0', 820, 820, 3154, -47.2040999999999968, -68.7119, 'S 47 12 14', 'O 68 42 42', 170, 153);
INSERT INTO bdc.mux_grid VALUES ('170/154', '0106000020E61000000100000001030000000100000005000000A6627AB9CD5851C0D00437900AC747C08A0646D0911E51C0CC43CDE174D847C0B2FD57A35F3551C0189216CEC94848C0CC598C8C9B6F51C01C53807C5F3748C0A6627AB9CD5851C0D00437900AC747C0', 821, 821, 3156, -48.0818000000000012, -69.0657000000000068, 'S 48 04 54', 'O 69 03 56', 170, 154);
INSERT INTO bdc.mux_grid VALUES ('170/155', '0106000020E610000001000000010300000001000000050000008CC7A31BB76F51C0CE04A03E573748C04E2B1C89943551C0622D53FCB94848C01A349D92094D51C0DABC4B16F0B848C058D024252C8751C0489498588DA748C08CC7A31BB76F51C0CE04A03E573748C0', 822, 822, 3157, -48.9585000000000008, -69.4295999999999935, 'S 48 57 30', 'O 69 25 46', 170, 155);
INSERT INTO bdc.mux_grid VALUES ('170/156', '0106000020E61000000100000001030000000100000005000000A4187D82498751C0D0C77A9084A748C058B2A5EB414D51C08E9F623CDFB848C0EE212F57696551C0228C3FDFF42849C03A8806EE709F51C064B457339A1749C0A4187D82498751C0D0C77A9084A748C0', 823, 823, 3158, -49.8342999999999989, -69.8041999999999945, 'S 49 50 03', 'O 69 48 15', 170, 156);
INSERT INTO bdc.mux_grid VALUES ('170/157', '0106000020E61000000100000001030000000100000005000000FA235F40909F51C055EC65D5901749C0CA76DA6CA56551C092A93FE7E22849C04860955A8B7E51C0C6AD5D4AD69849C0780D1A2E76B851C088F08338848749C0FA235F40909F51C055EC65D5901749C0', 824, 824, 3159, -50.7090000000000032, -70.1902000000000044, 'S 50 42 32', 'O 70 11 24', 170, 157);
INSERT INTO bdc.mux_grid VALUES ('170/158', '0106000020E61000000100000001030000000100000005000000223D56A097B851C024C0EA377A8749C06A1AFD7DCB7E51C01621061CC39849C01DAF421D7D9851C0AC7CBB4E92084AC0D4D19B3F49D251C0BA1BA06A49F749C0223D56A097B851C024C0EA377A8749C0', 825, 825, 3161, -51.5825999999999993, -70.5883999999999929, 'S 51 34 57', 'O 70 35 18', 170, 158);
INSERT INTO bdc.mux_grid VALUES ('170/159', '0106000020E61000000100000001030000000100000005000000DAA349016DD251C0A2C526B93EF749C0BCCB32A8C19851C05A8C31CF7D084AC0B6F9A3554DB351C01AC70FB426784AC0D4D1BAAEF8EC51C06200059EE7664AC0DAA349016DD251C0A2C526B93EF749C0', 826, 826, 3162, -52.4549999999999983, -70.9997000000000043, 'S 52 27 18', 'O 70 59 58', 170, 159);
INSERT INTO bdc.mux_grid VALUES ('170/94', '0106000020E61000000100000001030000000100000005000000FEACCE3632B24BC06E698975FAA7174055F1A27D973A4BC0A942A374E7181740E186FEDFD1534BC07289A4D0818313408A422A996CCB4BC037B08AD194121440FEACCE3632B24BC06E698975FAA71740', 827, 827, 3187, 5.37619999999999987, -54.9784999999999968, 'N 05 22 34', 'O 54 58 42', 170, 94);
INSERT INTO bdc.mux_grid VALUES ('170/95', '0106000020E610000001000000010300000001000000050000003BF1CC596ACB4BC00E28462192121440061099B6CD534BC0954C2FD67C8313401ACFABDCFB6C4BC07EE6AA3B0EDC0F404FB0DF7F98E44BC0B84EEC681C7D10403BF1CC596ACB4BC00E28462192121440', 828, 828, 3189, 4.48029999999999973, -55.1753, 'N 04 28 49', 'O 55 10 31', 170, 95);
INSERT INTO bdc.mux_grid VALUES ('170/96', '0106000020E61000000100000001030000000100000005000000A6234CA096E44BC0BD6C3D2B1A7D10402BAB9A69F86C4BC0C890F7FA05DC0F401195B07C1C864BC054993A0400B108408C0D62B3BAFD4BC005E2BD5F2ECF0940A6234CA096E44BC0BD6C3D2B1A7D1040', 829, 829, 3190, 3.58429999999999982, -55.3718000000000004, 'N 03 35 03', 'O 55 22 18', 170, 96);
INSERT INTO bdc.mux_grid VALUES ('170/97', '0106000020E61000000100000001030000000100000005000000C262B232B9FD4BC06D6C65C72ACF09408D394CBE19864BC0C819C973F9B00840E731BCE2359F4BC0FB641597DE8501401C5B2257D5164CC09EB7B1EA0FA40240C262B232B9FD4BC06D6C65C72ACF0940', 830, 830, 3191, 2.68829999999999991, -55.5679999999999978, 'N 02 41 17', 'O 55 34 04', 170, 97);
INSERT INTO bdc.mux_grid VALUES ('170/98', '0106000020E610000001000000010300000001000000050000006EC49E34D4164CC046D2A6330DA40240A6C7B4D7339F4BC0A83FC2B3D98501408DC4F12D4AB84BC04812141E5FB5F43F54C1DB8AEA2F4CC08737DD1DC6F1F63F6EC49E34D4164CC046D2A6330DA40240', 831, 831, 3192, 1.79220000000000002, -55.7640999999999991, 'N 01 47 31', 'O 55 45 50', 170, 98);
INSERT INTO bdc.mux_grid VALUES ('170/99', '0106000020E6100000010000000103000000010000000500000093C8F9C5E92F4CC03E06CC6FC2F1F63F95D04DD548B84BC0F4BD00AD58B5F43FAB05F47A5BD14BC09C3A4E30C47BD93FAAFD9F6BFC484CC0D7ADBD9DB536E13F93C8F9C5E92F4CC03E06CC6FC2F1F63F', 832, 832, 3193, 0.896100000000000008, -55.9600000000000009, 'N 00 53 45', 'O 55 57 35', 170, 99);
INSERT INTO bdc.mux_grid VALUES ('171/100', '0106000020E61000000100000001030000000100000005000000115EA7F785C44CC0DC0D24BEB136E13F76D2B4C7E44C4CC030AD07B6B77BD93FE1EF93D8F5654CC0C959525307DEDFBF7B7B860897DD4CC040EB118D5BECD6BF115EA7F785C44CC0DC0D24BEB136E13F', 833, 833, 3195, 0, -57.1210000000000022, 'N 00 00 00', 'O 57 07 15', 171, 100);
INSERT INTO bdc.mux_grid VALUES ('171/101', '0106000020E610000001000000010300000001000000050000004E23FBFD96DD4CC06C76E2565CECD6BF0C481FE3F5654CC0A8CE818906DEDFBF36E0427A077F4CC096FDAB51EE4DF6BF78BB1E95A8F64CC0862704C58311F4BF4E23FBFD96DD4CC06C76E2565CECD6BF', 834, 834, 3197, -0.896100000000000008, -57.3168000000000006, 'S 00 53 45', 'O 57 19 00', 171, 101);
INSERT INTO bdc.mux_grid VALUES ('171/102', '0106000020E61000000100000001030000000100000005000000AF07A1E7A8F64CC0CBBC373A8211F4BFC42B4336087F4CC026261ACEEA4DF6BF6D50FA6E1C984CC0155B579B245202C0562C5820BD0F4DC066266651F03301C0AF07A1E7A8F64CC0CBBC373A8211F4BF', 835, 835, 3199, -1.79220000000000002, -57.5127000000000024, 'S 01 47 31', 'O 57 30 45', 171, 102);
INSERT INTO bdc.mux_grid VALUES ('171/103', '0106000020E6100000010000000103000000010000000500000022450FD0BD0F4DC0DBFB01ADEE3301C063FBC8DC1D984CC0DBA42930215202C07020AED336B14CC0E4F73AA7437D09C02E6AF4C6D6284DC0E44E1324115F08C022450FD0BD0F4DC0DBFB01ADEE3301C0', 836, 836, 3200, -2.68829999999999991, -57.7087000000000003, 'S 02 41 17', 'O 57 42 31', 171, 103);
INSERT INTO bdc.mux_grid VALUES ('171/104', '0106000020E61000000100000001030000000100000005000000D3D233D4D7284DC02962E99F0E5F08C07F5DF9F338B14CC03AB407913E7D09C00891FBC758CA4CC082F04658275410C05C0636A8F7414DC0F58E6FBF1E8A0FC0D3D233D4D7284DC02962E99F0E5F08C0', 837, 837, 3201, -3.58429999999999982, -57.9050000000000011, 'S 03 35 03', 'O 57 54 17', 171, 104);
INSERT INTO bdc.mux_grid VALUES ('171/105', '0106000020E6100000010000000103000000010000000500000006F37D13F9414DC01E274D5A1B8A0FC0B60AC79B5BCA4CC034E973F6235410C0B493356F84E34CC04DBDD50CA0E913C0027CECE6215B4DC0AA6788C3895A13C006F37D13F9414DC01E274D5A1B8A0FC0', 838, 838, 3202, -4.48029999999999973, -58.1013999999999982, 'S 04 28 49', 'O 58 06 05', 171, 105);
INSERT INTO bdc.mux_grid VALUES ('171/106', '0106000020E61000000100000001030000000100000005000000AF55EAB0235B4DC00886AB9F875A13C0BD75DBF787E34CC00A37ABD29BE913C032EF74F1BBFC4CC02AE76221097F17C024CF83AA57744DC0293663EEF4EF16C0AF55EAB0235B4DC00886AB9F875A13C0', 839, 839, 3203, -5.37619999999999987, -58.2982999999999976, 'S 05 22 34', 'O 58 17 53', 171, 106);
INSERT INTO bdc.mux_grid VALUES ('171/107', '0106000020E610000001000000010300000001000000050000001CE612D459744DC0634D3458F2EF16C02B48A730C0FC4CC0AAA6D90C047F17C09F54AD7C01164DC0755CB3C45F141BC090F218209B8D4DC02E030E104E851AC01CE612D459744DC0634D3458F2EF16C0', 840, 840, 3205, -6.27210000000000001, -58.4954999999999998, 'S 06 16 19', 'O 58 29 43', 171, 107);
INSERT INTO bdc.mux_grid VALUES ('171/108', '0106000020E61000000100000001030000000100000005000000CE6143AA9D8D4DC099C04E064B851AC0B0D4777406164DC04FEE58D359141BC02E8EC845572F4DC02328F423A1A91EC04C1B947BEEA64DC06CFAE956921A1EC0CE6143AA9D8D4DC099C04E064B851AC0', 841, 841, 3206, -7.16790000000000038, -58.6931000000000012, 'S 07 10 04', 'O 58 41 35', 171, 108);
INSERT INTO bdc.mux_grid VALUES ('171/109', '0106000020E61000000100000001030000000100000005000000CDDC9367F1A64DC086C722D88E1A1EC07AA392F85C2F4DC04B5AE8529AA91EC0BFF5C889BF484DC059B23835651F21C0122FCAF853C04DC0F7E8D577DFD720C0CDDC9367F1A64DC086C722D88E1A1EC0', 842, 842, 3208, -8.06359999999999921, -58.8913000000000011, 'S 08 03 49', 'O 58 53 28', 171, 109);
INSERT INTO bdc.mux_grid VALUES ('171/110', '0106000020E6100000010000000103000000010000000500000059640A4857C04DC0BF25157DDDD720C0714B58FAC5484DC008A5315B611F21C03973F48E3C624DC03F8DA360ECE922C0208CA6DCCDD94DC0F60D878268A222C059640A4857C04DC0BF25157DDDD720C0', 843, 843, 3210, -8.95919999999999916, -59.0900999999999996, 'S 08 57 33', 'O 59 05 24', 171, 110);
INSERT INTO bdc.mux_grid VALUES ('171/111', '0106000020E610000001000000010300000001000000050000004EFCC490D1D94DC06DA4714B66A222C0F0D76FC043624DC06AC93813E8E922C0395009A6D07B4DC0C88D85A764B424C099745E765EF34DC0CB68BEDFE26C24C04EFCC490D1D94DC06DA4714B66A222C0', 844, 844, 3211, -9.85479999999999912, -59.2894999999999968, 'S 09 51 17', 'O 59 17 22', 171, 111);
INSERT INTO bdc.mux_grid VALUES ('171/112', '0106000020E610000001000000010300000001000000050000003A432D9162F34DC0008B3D6BE06C24C0B307FC9BD87B4DC07F6D98E45FB424C00D3F7E2B7E954DC03A73B79BCC7E26C0927AAF20080D4EC0BB905C224D3726C03A432D9162F34DC0008B3D6BE06C24C0', 845, 845, 3212, -10.7501999999999995, -59.4896999999999991, 'S 10 45 00', 'O 59 29 22', 171, 112);
INSERT INTO bdc.mux_grid VALUES ('171/113', '0106000020E610000001000000010300000001000000050000008A1A37A40C0D4EC0FBF4386F4A3726C05BC6DBE986954DC01CFAEA60C77E26C02B0ACF8847AF4DC0354D6CCD224928C05A5E2A43CD264EC01448BADBA50128C08A1A37A40C0D4EC0FBF4386F4A3726C0', 846, 846, 3213, -11.6454000000000004, -59.6906999999999996, 'S 11 38 43', 'O 59 41 26', 171, 113);
INSERT INTO bdc.mux_grid VALUES ('171/114', '0106000020E610000001000000010300000001000000050000005AC2AB31D2264EC0A0D99AE8A20128C0A453F71351AF4DC004A022181D4928C0E575D7352FC94DC059F4F8CA65132AC098E48B53B0404EC0F52D719BEBCB29C05AC2AB31D2264EC0A0D99AE8A20128C0', 847, 847, 3214, -12.5404999999999998, -59.8924999999999983, 'S 12 32 25', 'O 59 53 33', 171, 114);
INSERT INTO bdc.mux_grid VALUES ('171/115', '0106000020E6100000010000000103000000010000000500000027F582AFB5404EC04094D966E8CB29C0BCA69B9239C94DC03B8350985F132AC0EAFB3DBA37E34DC073F2952094DD2BC0554A25D7B35A4EC078031FEF1C962BC027F582AFB5404EC04094D966E8CB29C0', 848, 848, 3216, -13.4354999999999993, -60.0953000000000017, 'S 13 26 07', 'O 60 05 43', 171, 115);
INSERT INTO bdc.mux_grid VALUES ('171/116', '0106000020E61000000100000001030000000100000005000000E4A14BA3B95A4EC05EFF6D7719962BC0D7B0E5ED42E34DC02E52666D8DDD2BC0A721F0AE63FD4DC097471B58ACA72DC0B5125664DA744EC0CAF4226238602DC0E4A14BA3B95A4EC05EFF6D7719962BC0', 849, 849, 3217, -14.3302999999999994, -60.299199999999999, 'S 14 19 49', 'O 60 17 57', 171, 116);
INSERT INTO bdc.mux_grid VALUES ('171/117', '0106000020E610000001000000010300000001000000050000009707A6A3E0744EC0448F90A534602DC0014A3FBF6FFD4DC0F8B0F120A5A72DC03854B2BFB5174EC03D63B5F8AC712FC0CD1119A4268F4EC08741547D3C2A2FC09707A6A3E0744EC0448F90A534602DC0', 850, 850, 3218, -15.2249999999999996, -60.5041999999999973, 'S 15 13 29', 'O 60 30 15', 171, 117);
INSERT INTO bdc.mux_grid VALUES ('171/118', '0106000020E610000001000000010300000001000000050000008212D1592D8F4EC024C9EF79382A2FC0B0A6EFB2C2174EC0A0D6D039A5712FC0DF4DC5AC30324EC0C3534943CA9D30C0B3B9A6539BA94EC007CD58E3137A30C08212D1592D8F4EC024C9EF79382A2FC0', 851, 851, 3221, -16.1193999999999988, -60.7102999999999966, 'S 16 07 09', 'O 60 42 37', 171, 118);
INSERT INTO bdc.mux_grid VALUES ('171/119', '0106000020E61000000100000001030000000100000005000000A2024D83A2A94EC06CB52FBD117A30C06C6BC1893E324EC004D4EF1DC69D30C02C44A34CD74C4EC0EF6044C1B08231C062DB2E463BC44EC057428460FC5E31C0A2024D83A2A94EC06CB52FBD117A30C0', 852, 852, 3222, -17.0137, -60.9177999999999997, 'S 17 00 49', 'O 60 55 04', 171, 119);
INSERT INTO bdc.mux_grid VALUES ('171/120', '0106000020E610000001000000010300000001000000050000003B8D95F342C44EC032CBBF14FA5E31C0B891C01AE64C4EC0BA51CE53AC8231C06A3ED78DAC674EC0307FD834896732C0EC39AC6609DF4EC0A8F8C9F5D64332C03B8D95F342C44EC032CBBF14FA5E31C0', 853, 853, 3223, -17.9076999999999984, -61.1266000000000034, 'S 17 54 27', 'O 61 07 35', 171, 120);
INSERT INTO bdc.mux_grid VALUES ('171/121', '0106000020E6100000010000000103000000010000000500000003D9F59511DF4EC056932D83D44332C068861255BC674EC0135EE27C846732C0BD33F178B3824EC0606C7DDA524C33C05786D4B908FA4EC0A3A1C8E0A22833C003D9F59511DF4EC056932D83D44332C0', 854, 854, 3224, -18.8016000000000005, -61.3369, 'S 18 48 05', 'O 61 20 12', 171, 121);
INSERT INTO bdc.mux_grid VALUES ('171/122', '0106000020E61000000100000001030000000100000005000000ADEC786F11FA4EC06A3AFE45A02833C07C21EB41C4824EC0A3B472D54D4C33C0E0C69932EF9D4EC0C5DE59EC0C3134C0149227603C154FC08C64E55C5F0D34C0ADEC786F11FA4EC06A3AFE45A02833C0', 855, 855, 3225, -19.6951000000000001, -61.5488, 'S 19 41 42', 'O 61 32 55', 171, 122);
INSERT INTO bdc.mux_grid VALUES ('171/123', '0106000020E61000000100000001030000000100000005000000025BF9A045154FC090C37B985C0D34C0894EA106019E4EC0A8EC7197073134C00DBCC8FD62B94EC0308E01A2B61535C084C82098A7304FC019650BA30BF234C0025BF9A045154FC090C37B985C0D34C0', 856, 856, 3226, -20.5884999999999998, -61.7623000000000033, 'S 20 35 18', 'O 61 45 44', 171, 123);
INSERT INTO bdc.mux_grid VALUES ('171/124', '0106000020E61000000100000001030000000100000005000000C1475369B1304FC0C66574B308F234C05F85E6E675B94EC0EC343CFAB01535C0848D213E12D54EC05CCB2C304FFA35C0E44F8EC04D4C4FC036FC64E9A6D635C0C1475369B1304FC0C66574B308F234C0', 857, 857, 3227, -21.4816000000000003, -61.9774999999999991, 'S 21 28 53', 'O 61 58 39', 171, 124);
INSERT INTO bdc.mux_grid VALUES ('171/125', '0106000020E61000000100000001030000000100000005000000341ABC27584C4FC0F298F3CCA3D635C06679244726D54EC073964E3249FA35C0DAD9797A00F14EC0DD1769C8D5DE36C0A67A115B32684FC05B1A0E6330BB36C0341ABC27584C4FC0F298F3CCA3D635C0', 858, 858, 3228, -22.3744000000000014, -62.1946000000000012, 'S 22 22 27', 'O 62 11 40', 171, 125);
INSERT INTO bdc.mux_grid VALUES ('171/126', '0106000020E61000000100000001030000000100000005000000F293435E3D684FC0D946F4172DBB36C04BBE04AF15F14EC0A42FF770CFDE36C0F7C38D5F310D4FC05111C29849C337C09D99CC0E59844FC08628BF3FA79F37C0F293435E3D684FC0D946F4172DBB36C0', 859, 859, 3231, -23.2669999999999995, -62.4136999999999986, 'S 23 16 01', 'O 62 24 49', 171, 126);
INSERT INTO bdc.mux_grid VALUES ('171/127', '0106000020E610000001000000010300000001000000050000006B5282B464844FC0AA770BC4A39F37C0137B26CC470D4FC011BAFDE342C337C095C4E6C2A8294FC076F961CBA9A738C0EF9B42ABC5A04FC00EB76FAB0A8438C06B5282B464844FC0AA770BC4A39F37C0', 860, 860, 3232, -24.1593000000000018, -62.6349000000000018, 'S 24 09 33', 'O 62 38 05', 171, 127);
INSERT INTO bdc.mux_grid VALUES ('171/128', '0106000020E6100000010000000103000000010000000500000098387AFAD1A04FC067C40AFD068438C027B30675C0294FC041A243B5A2A738C05DE8F9A56A464FC019132986F58B39C0CE6D6D2B7CBD4FC04035F0CD596839C098387AFAD1A04FC067C40AFD068438C0', 861, 861, 3233, -25.0512000000000015, -62.8582999999999998, 'S 25 03 04', 'O 62 51 29', 171, 128);
INSERT INTO bdc.mux_grid VALUES ('171/129', '0106000020E61000000100000001030000000100000005000000E4A1AD2B89BD4FC025CF99EA556839C0482220AC83464FC0D0E85A0AEE8B39C0A5F682397B634FC0B0EF3AEA2B703AC0437610B980DA4FC006D679CA934C3AC0E4A1AD2B89BD4FC025CF99EA556839C0', 862, 862, 3234, -25.9429000000000016, -63.0840000000000032, 'S 25 56 34', 'O 63 05 02', 171, 129);
INSERT INTO bdc.mux_grid VALUES ('171/130', '0106000020E6100000010000000103000000010000000500000041D572728EDA4FC047DEC5AF8F4C3AC0192748A395634FC003E9120424703AC0458F22E1DE804FC0E0BE80134C543BC06D3D4DB0D7F74FC025B433BFB7303BC041D572728EDA4FC047DEC5AF8F4C3AC0', 863, 863, 3236, -26.8341999999999992, -63.3121000000000009, 'S 26 50 03', 'O 63 18 43', 171, 130);
INSERT INTO bdc.mux_grid VALUES ('171/131', '0106000020E6100000010000000103000000010000000500000091AE892BE6F74FC03CB3866AB3303BC095DA4EBFFA804FC0F010FABD43543BC0E1FE45379A9E4FC0D8891F1855383CC06E69C0D1C20A50C0232CACC4C4143CC091AE892BE6F74FC03CB3866AB3303BC0', 864, 864, 3237, -27.7251000000000012, -63.542900000000003, 'S 27 43 30', 'O 63 32 34', 171, 131);
INSERT INTO bdc.mux_grid VALUES ('171/132', '0106000020E610000001000000010300000001000000050000007018FD74CA0A50C0C38A3733C0143CC04412E99BB79E4FC03076D34D4C383CC0D73E6011B2BC4FC0262BE107461C3DC0BCAEB8AFC71950C0B73F45EDB9F83CC07018FD74CA0A50C0C38A3733C0143CC0', 865, 865, 3238, -28.6157000000000004, -63.7764000000000024, 'S 28 36 56', 'O 63 46 35', 171, 132);
INSERT INTO bdc.mux_grid VALUES ('171/133', '0106000020E6100000010000000103000000010000000500000008ACA1BDCF1950C01F20031CB5F83CC012C6EB0FD1BC4FC00316FFC23C1C3DC0096A7C842BDB4FC0E1BA8EEB1D003EC002FEE9F7FC2850C0FDC4924496DC3DC008ACA1BDCF1950C01F20031CB5F83CC0', 866, 866, 3239, -29.5060000000000002, -64.0127999999999986, 'S 29 30 21', 'O 64 00 46', 171, 133);
INSERT INTO bdc.mux_grid VALUES ('171/134', '0106000020E610000001000000010300000001000000050000001C33F175052950C0116F413091DC3DC0DD36E1314CDB4FC02273D32514003EC0A0E932EA0BFA4FC0BCEC3AC4DBE33EC07A0C1A52653850C0ADE8A8CE58C03EC01C33F175052950C0116F413091DC3DC0', 867, 867, 3240, -30.3958000000000013, -64.252200000000002, 'S 30 23 44', 'O 64 15 07', 171, 134);
INSERT INTO bdc.mux_grid VALUES ('171/135', '0106000020E61000000100000001030000000100000005000000F6E41D466E3850C0E9BDC57353C03EC09911015D2EFA4FC02E11E776D1E33EC054D00573AC0C50C0DBCA7A8A7EC73FC07E2CA38A034850C09677598700A43FC0F6E41D466E3850C0E9BDC57353C03EC0', 868, 868, 3242, -31.2852999999999994, -64.4949000000000012, 'S 31 17 06', 'O 64 29 41', 171, 135);
INSERT INTO bdc.mux_grid VALUES ('171/136', '0106000020E6100000010000000103000000010000000500000090E7F7FA0C4850C022601BE2FAA33FC090F84A9BBE0C50C0DF2F48AE73C73FC01A50AC358C1C50C04C78C596825540C01A3F5995DA5750C06C10AF30C64340C090E7F7FA0C4850C022601BE2FAA33FC0', 869, 869, 3244, -32.1743000000000023, -64.7408999999999963, 'S 32 10 27', 'O 64 44 27', 171, 136);
INSERT INTO bdc.mux_grid VALUES ('171/137', '0106000020E610000001000000010300000001000000050000005A3CD388E45750C03AB1D736C34340C008E0ED599F1C50C0307650DD7C5540C0841CCB61A82C50C0FCA02F4937C740C0D678B090ED6750C008DCB6A27DB540C05A3CD388E45750C03AB1D736C34340C0', 870, 870, 3245, -33.0628999999999991, -64.9904999999999973, 'S 33 03 46', 'O 64 59 25', 171, 137);
INSERT INTO bdc.mux_grid VALUES ('171/138', '0106000020E610000001000000010300000001000000050000005A9DAF0EF86750C0B292727F7AB540C00AF83190BC2C50C08ADD224031C740C0F66FAF4A043D50C0FC694DC9DC3841C046152DC93F7850C0221F9D08262741C05A9DAF0EF86750C0B292727F7AB540C0', 871, 871, 3246, -33.9510000000000005, -65.2438999999999965, 'S 33 57 03', 'O 65 14 38', 171, 138);
INSERT INTO bdc.mux_grid VALUES ('171/139', '0106000020E61000000100000001030000000100000005000000FA6BA9D94A7850C0BCD489B9222741C0A2FE8692193D50C01CF7156CD63841C0FA860176A34D50C056B4B67D72AA41C050F423BDD48850C0F4912ACBBE9841C0FA6BA9D94A7850C0BCD489B9222741C0', 872, 872, 3247, -34.8387000000000029, -65.5013000000000005, 'S 34 50 19', 'O 65 30 04', 171, 139);
INSERT INTO bdc.mux_grid VALUES ('171/140', '0106000020E6100000010000000103000000010000000500000042AEBB68E08850C06C7FB44DBB9841C0D03CD2E7B94D50C01CD362C76BAA41C05EA7EB9F895E50C072D829C6F71B42C0D218D520B09950C0C2847B4C470A42C042AEBB68E08850C06C7FB44DBB9841C0', 873, 873, 3249, -35.7257999999999996, -65.7629000000000019, 'S 35 43 33', 'O 65 45 46', 171, 140);
INSERT INTO bdc.mux_grid VALUES ('171/141', '0106000020E61000000100000001030000000100000005000000B51ADC70BC9950C0328CD89D430A42C01479984DA15E50C02C2A60B1F01B42C0027FA6BFBA6F50C0EE78DBFA6B8D42C0A020EAE2D5AA50C0F4DA53E7BE7B42C0B51ADC70BC9950C0328CD89D430A42C0', 874, 874, 3250, -36.6124999999999972, -66.028899999999993, 'S 36 36 45', 'O 66 01 44', 171, 141);
INSERT INTO bdc.mux_grid VALUES ('171/142', '0106000020E6100000010000000103000000010000000500000024507BE1E2AA50C0005B7E04BB7B42C034968DBCD36F50C06037D181648D42C0F060760C3B8150C07A39B46BCEFE42C0E01A64314ABC50C01C5D61EE24ED42C024507BE1E2AA50C0005B7E04BB7B42C0', 875, 875, 3251, -37.4986000000000033, -66.2997000000000014, 'S 37 29 55', 'O 66 17 58', 171, 142);
INSERT INTO bdc.mux_grid VALUES ('171/143', '0106000020E610000001000000010300000001000000050000009C9E74E957BC50C0306F12D420ED42C01881956D558150C084542288C6FE42C0B07426030F9350C0073C7A5F1E7043C03692057F11CE50C0B4566AAB785E43C09C9E74E957BC50C0306F12D420ED42C0', 876, 876, 3253, -38.3841999999999999, -66.5752999999999986, 'S 38 23 03', 'O 66 34 31', 171, 143);
INSERT INTO bdc.mux_grid VALUES ('171/144', '0106000020E610000001000000010300000001000000050000008C4E7AFC1FCE50C0FC611356745E43C0DC8343DF2A9350C07A3A910A167043C02498106C3BA550C0EA0AE4125BE143C0D862478930E050C06A32665EB9CF43C08C4E7AFC1FCE50C0FC611356745E43C0', 877, 877, 3255, -39.2691999999999979, -66.8562000000000012, 'S 39 16 09', 'O 66 51 22', 171, 144);
INSERT INTO bdc.mux_grid VALUES ('171/145', '0106000020E61000000100000001030000000100000005000000B0F70CD93FE050C00EBF29CAB4CF43C008D7E6DB58A550C098843E4552E143C0FCB2C261C5B750C0622F92B7835244C0A2D3E85EACF250C0D8697D3CE64044C0B0F70CD93FE050C00EBF29CAB4CF43C0', 878, 878, 3257, -40.1535999999999973, -67.1426000000000016, 'S 40 09 13', 'O 67 08 33', 171, 145);
INSERT INTO bdc.mux_grid VALUES ('171/146', '0106000020E610000001000000010300000001000000050000007C710E8FBCF250C0BE1A2765E14044C0E2403580E4B750C0BAB125697A5244C094825458B2CA50C00676EC7297C344C030B32D678A0551C00ADFED6EFEB144C07C710E8FBCF250C0BE1A2765E14044C0', 879, 879, 3258, -41.0373999999999981, -67.434899999999999, 'S 41 02 14', 'O 67 26 05', 171, 146);
INSERT INTO bdc.mux_grid VALUES ('171/147', '0106000020E61000000100000001030000000100000005000000BC2C03879B0551C0D473E94FF9B144C0ECDFA642D3CA50C0C09DF89A8DC344C05A7D832508DE50C05849DF5C953445C02ACADF69D01851C06C1FD011012345C0BC2C03879B0551C0D473E94FF9B144C0', 880, 880, 3259, -41.9206000000000003, -67.7334000000000032, 'S 41 55 14', 'O 67 44 00', 171, 147);
INSERT INTO bdc.mux_grid VALUES ('171/148', '0106000020E61000000100000001030000000100000005000000C84F178AE21851C0F25D1FA6FB2245C056E198FB2ADE50C0A8D1DAF18A3445C0DA80AD09CDF150C0282E757E7CA545C04CEF2B98842C51C072BAB932ED9345C0C84F178AE21851C0F25D1FA6FB2245C0', 881, 881, 3261, -42.8029999999999973, -68.0384999999999991, 'S 42 48 10', 'O 68 02 18', 171, 148);
INSERT INTO bdc.mux_grid VALUES ('171/149', '0106000020E61000000100000001030000000100000005000000B0FDFFCA972C51C0BE16E974E79345C05EE84FEEF1F150C0A0B0F87571A545C0BA6DC6B9070651C038BC47D04B1646C00C837696AD4051C0562238CFC10446C0B0FDFFCA972C51C0BE16E974E79345C0', 882, 882, 3262, -43.6848000000000027, -68.3504999999999967, 'S 43 41 05', 'O 68 21 01', 171, 149);
INSERT INTO bdc.mux_grid VALUES ('171/150', '0106000020E610000001000000010300000001000000050000003A92D4EFC14051C0D0FA51B9BB0446C04E80F6D22E0651C026CCF51E401646C07AFC686ABF1A51C018D1C238028746C0660E4787525551C0C2FF1ED37D7546C03A92D4EFC14051C0D0FA51B9BB0446C0', 883, 883, 3263, -44.565800000000003, -68.6698999999999984, 'S 44 33 56', 'O 68 40 11', 171, 150);
INSERT INTO bdc.mux_grid VALUES ('171/151', '0106000020E6100000010000000103000000010000000500000080BCFF1C685551C09C359D5E777546C0F4FCB7E1E81A51C0DE152DD2F58646C07CBB27DCFB2F51C048DF338A9EF746C00A7B6F177B6A51C004FFA31620E646C080BCFF1C685551C09C359D5E777546C0', 884, 884, 3265, -45.4461000000000013, -68.9971000000000032, 'S 45 26 45', 'O 68 59 49', 171, 151);
INSERT INTO bdc.mux_grid VALUES ('171/152', '0106000020E610000001000000010300000001000000050000003CF76C01926A51C011B05F3C19E646C07CF91CDF273051C000BEBC6091F746C072B94869C54551C0FE529E801F6847C034B7988B2F8051C00E45415CA75647C03CF76C01926A51C011B05F3C19E646C0', 885, 885, 3266, -46.3254999999999981, -69.3325999999999993, 'S 46 19 31', 'O 69 19 57', 171, 152);
INSERT INTO bdc.mux_grid VALUES ('171/153', '0106000020E6100000010000000103000000010000000500000070581CE4478051C094606014A05647C0222BD429F44551C0C4A85685116847C0A0C41C15255C51C068EB4CBF83D847C0ECF164CF789651C038A3564E12C747C070581CE4478051C094606014A05647C0', 886, 886, 3267, -47.2040999999999968, -69.6770999999999958, 'S 47 12 14', 'O 69 40 37', 171, 153);
INSERT INTO bdc.mux_grid VALUES ('171/154', '0106000020E610000001000000010300000001000000050000007C164DB3929651C0940437900AC747C060BA18CA565C51C09043CDE174D847C070B12A9D247351C0689116CEC94848C08A0D5F8660AD51C06C52807C5F3748C07C164DB3929651C0940437900AC747C0', 887, 887, 3270, -48.0818000000000012, -70.0309000000000026, 'S 48 04 54', 'O 70 01 51', 171, 154);
INSERT INTO bdc.mux_grid VALUES ('171/155', '0106000020E61000000100000001030000000100000005000000187B76157CAD51C02C04A03E573748C0DCDEEE82597351C0BE2C53FCB94848C0C4E76F8CCE8A51C0BABC4B16F0B848C00284F71EF1C451C0289498588DA748C0187B76157CAD51C02C04A03E573748C0', 888, 888, 3272, -48.9585000000000008, -70.3947000000000003, 'S 48 57 30', 'O 70 23 41', 171, 155);
INSERT INTO bdc.mux_grid VALUES ('171/156', '0106000020E6100000010000000103000000010000000500000064CC4F7C0EC551C0AAC77A9084A748C05C6678E5068B51C0549F623CDFB848C0F2D501512EA351C0EE8B3FDFF42849C0FA3BD9E735DD51C045B457339A1749C064CC4F7C0EC551C0AAC77A9084A748C0', 889, 889, 3273, -49.8342999999999989, -70.7693000000000012, 'S 49 50 03', 'O 70 46 09', 171, 156);
INSERT INTO bdc.mux_grid VALUES ('171/157', '0106000020E61000000100000001030000000100000005000000AED7313A55DD51C038EC65D5901749C0C42AAD666AA351C063A93FE7E22849C04414685450BC51C09EAD5D4AD69849C02EC1EC273BF651C074F08338848749C0AED7313A55DD51C038EC65D5901749C0', 890, 890, 3274, -50.7090000000000032, -71.1552999999999969, 'S 50 42 32', 'O 71 09 19', 171, 157);
INSERT INTO bdc.mux_grid VALUES ('171/158', '0106000020E610000001000000010300000001000000050000009CF0289A5CF651C022C0EA377A8749C06ECECF7790BC51C0EC20061CC39849C02263151742D651C0887CBB4E92084AC050856E390E1052C0BE1BA06A49F749C09CF0289A5CF651C022C0EA377A8749C0', 891, 891, 3275, -51.5825999999999993, -71.553600000000003, 'S 51 34 57', 'O 71 33 12', 171, 158);
INSERT INTO bdc.mux_grid VALUES ('171/94', '0106000020E610000001000000010300000001000000050000009714742ABC2D4CC056698975FAA717400159487121B64BC0A542A374E71817408AEEA3D35BCF4BC0B389A4D08183134021AACF8CF6464CC064B08AD1941214409714742ABC2D4CC056698975FAA71740', 892, 892, 3299, 5.37619999999999987, -55.9436000000000035, 'N 05 22 34', 'O 55 56 37', 171, 94);
INSERT INTO bdc.mux_grid VALUES ('171/95', '0106000020E61000000100000001030000000100000005000000DF58724DF4464CC04728462192121440A1773EAA57CF4BC0C44C2FD67C831340B73651D085E84BC069E6AA3B0EDC0F40F417857322604CC0B64EEC681C7D1040DF58724DF4464CC04728462192121440', 893, 893, 3300, 4.48029999999999973, -56.140500000000003, 'N 04 28 49', 'O 56 08 25', 171, 95);
INSERT INTO bdc.mux_grid VALUES ('171/96', '0106000020E61000000100000001030000000100000005000000458BF19320604CC0B26C3D2B1A7D1040D212405D82E84BC0CA90F7FA05DC0F40B7FC5570A6014CC0CE993A0400B108402A7507A744794CC06BE2BD5F2ECF0940458BF19320604CC0B26C3D2B1A7D1040', 894, 894, 3301, 3.58429999999999982, -56.3369, 'N 03 35 03', 'O 56 20 12', 171, 96);
INSERT INTO bdc.mux_grid VALUES ('171/97', '0106000020E610000001000000010300000001000000050000006BCA572643794CC0F06C65C72ACF09402EA1F1B1A3014CC0351AC973F9B00840889961D6BF1A4CC0F1641597DE850140C4C2C74A5F924CC0ACB7B1EA0FA402406BCA572643794CC0F06C65C72ACF0940', 895, 895, 3302, 2.68829999999999991, -56.5332000000000008, 'N 02 41 17', 'O 56 31 59', 171, 97);
INSERT INTO bdc.mux_grid VALUES ('171/98', '0106000020E610000001000000010300000001000000050000000B2C44285E924CC036D2A6330DA402404D2F5ACBBD1A4CC0AD3FC2B3D9850140322C9721D4334CC0F812141E5FB5F43FF128817E74AB4CC00B38DD1DC6F1F63F0B2C44285E924CC036D2A6330DA40240', 896, 896, 3303, 1.79220000000000002, -56.7291999999999987, 'N 01 47 31', 'O 56 43 45', 171, 98);
INSERT INTO bdc.mux_grid VALUES ('171/99', '0106000020E6100000010000000103000000010000000500000035309FB973AB4CC0D906CC6FC2F1F63F3738F3C8D2334CC093BE00AD58B5F43F4F6D996EE54C4CC0D83A4E30C47BD93F4E65455F86C44CC0F8ADBD9DB536E13F35309FB973AB4CC0D906CC6FC2F1F63F', 897, 897, 3305, 0.896100000000000008, -56.9251000000000005, 'N 00 53 45', 'O 56 55 30', 171, 99);
INSERT INTO bdc.mux_grid VALUES ('172/100', '0106000020E61000000100000001030000000100000005000000B5C54CEB0F404DC0C10D24BEB136E13F173A5ABB6EC84CC0A0AC07B6B77BD93F815739CC7FE14CC04A59525307DEDFBF1FE32BFC20594DC068EA118D5BECD6BFB5C54CEB0F404DC0C10D24BEB136E13F', 898, 898, 3306, 0, -58.0861000000000018, 'N 00 00 00', 'O 58 05 09', 172, 100);
INSERT INTO bdc.mux_grid VALUES ('172/101', '0106000020E61000000100000001030000000100000005000000F28AA0F120594DC0A775E2565CECD6BFABAFC4D67FE14CC04ECE818906DEDFBFD547E86D91FA4CC01BFEAB51EE4DF6BF1C23C48832724DC0F12704C58311F4BFF28AA0F120594DC0A775E2565CECD6BF', 899, 899, 3309, -0.896100000000000008, -58.2819000000000003, 'S 00 53 45', 'O 58 16 54', 172, 101);
INSERT INTO bdc.mux_grid VALUES ('172/102', '0106000020E61000000100000001030000000100000005000000576F46DB32724DC029BD373A8211F4BF6593E82992FA4CC0AC261ACEEA4DF6BF0CB89F62A6134DC0175B579B245202C0FE93FD13478B4DC056266651F03301C0576F46DB32724DC029BD373A8211F4BF', 900, 900, 3310, -1.79220000000000002, -58.477800000000002, 'S 01 47 31', 'O 58 28 40', 172, 102);
INSERT INTO bdc.mux_grid VALUES ('172/103', '0106000020E61000000100000001030000000100000005000000BFACB4C3478B4DC0E6FB01ADEE3301C006636ED0A7134DC0D2A42930215202C0148853C7C02C4DC01EF83AA7437D09C0CBD199BA60A44DC0334F1324115F08C0BFACB4C3478B4DC0E6FB01ADEE3301C0', 901, 901, 3311, -2.68829999999999991, -58.6739000000000033, 'S 02 41 17', 'O 58 40 25', 172, 103);
INSERT INTO bdc.mux_grid VALUES ('172/104', '0106000020E610000001000000010300000001000000050000007E3AD9C761A44DC05462E99F0E5F08C018C59EE7C22C4DC08DB407913E7D09C0A1F8A0BBE2454DC0AAF04658275410C0066EDB9B81BD4DC01A8F6FBF1E8A0FC07E3AD9C761A44DC05462E99F0E5F08C0', 902, 902, 3312, -3.58429999999999982, -58.8701000000000008, 'S 03 35 03', 'O 58 52 12', 172, 104);
INSERT INTO bdc.mux_grid VALUES ('172/105', '0106000020E61000000100000001030000000100000005000000AC5A230783BD4DC050274D5A1B8A0FC052726C8FE5454DC057E973F6235410C052FBDA620E5F4DC0B3BDD50CA0E913C0AAE391DAABD64DC0046888C3895A13C0AC5A230783BD4DC050274D5A1B8A0FC0', 903, 903, 3313, -4.48029999999999973, -59.0666000000000011, 'S 04 28 49', 'O 59 03 59', 172, 105);
INSERT INTO bdc.mux_grid VALUES ('172/106', '0106000020E610000001000000010300000001000000050000005ABD8FA4ADD64DC06386AB9F875A13C054DD80EB115F4DC07737ABD29BE913C0C3561AE545784DC096E66221097F17C0C836299EE1EF4DC0813563EEF4EF16C05ABD8FA4ADD64DC06386AB9F875A13C0', 904, 904, 3315, -5.37619999999999987, -59.2633999999999972, 'S 05 22 34', 'O 59 15 48', 172, 106);
INSERT INTO bdc.mux_grid VALUES ('172/107', '0106000020E61000000100000001030000000100000005000000C04DB8C7E3EF4DC0BA4C3458F2EF16C0BEAF4C244A784DC015A6D90C047F17C03ABC52708B914DC0DF5CB3C45F141BC03B5ABE1325094EC084030E104E851AC0C04DB8C7E3EF4DC0BA4C3458F2EF16C0', 905, 905, 3316, -6.27210000000000001, -59.4605999999999995, 'S 06 16 19', 'O 59 27 38', 172, 107);
INSERT INTO bdc.mux_grid VALUES ('172/108', '0106000020E6100000010000000103000000010000000500000081C9E89D27094EC0E4C04E064B851AC0523C1D6890914DC0AFEE58D359141BC0CEF56D39E1AA4DC00328F423A1A91EC0FA82396F78224EC038FAE956921A1EC081C9E89D27094EC0E4C04E064B851AC0', 906, 906, 3317, -7.16790000000000038, -59.658299999999997, 'S 07 10 04', 'O 59 39 29', 172, 108);
INSERT INTO bdc.mux_grid VALUES ('172/109', '0106000020E610000001000000010300000001000000050000008144395B7B224EC051C722D88E1A1EC00B0B38ECE6AA4DC03C5AE8529AA91EC0535D6E7D49C44DC092B23835651F21C0C9966FECDD3B4EC01AE9D577DFD720C08144395B7B224EC051C722D88E1A1EC0', 907, 907, 3320, -8.06359999999999921, -59.8564000000000007, 'S 08 03 49', 'O 59 51 23', 172, 109);
INSERT INTO bdc.mux_grid VALUES ('172/110', '0106000020E61000000100000001030000000100000005000000EACBAF3BE13B4EC0F825157DDDD720C005B3FDED4FC44DC041A5315B611F21C0CCDA9982C6DD4DC0788DA360ECE922C0B4F34BD057554EC02E0E878268A222C0EACBAF3BE13B4EC0F825157DDDD720C0', 908, 908, 3321, -8.95919999999999916, -60.0551999999999992, 'S 08 57 33', 'O 60 03 18', 172, 110);
INSERT INTO bdc.mux_grid VALUES ('172/111', '0106000020E6100000010000000103000000010000000500000000646A845B554EC092A4714B66A222C07E3F15B4CDDD4DC0A4C93813E8E922C0C9B7AE995AF74DC0018E85A764B424C04BDC036AE86E4EC0F068BEDFE26C24C000646A845B554EC092A4714B66A222C0', 909, 909, 3322, -9.85479999999999912, -60.2546999999999997, 'S 09 51 17', 'O 60 15 16', 172, 111);
INSERT INTO bdc.mux_grid VALUES ('172/112', '0106000020E6100000010000000103000000010000000500000005ABD284EC6E4EC0198B3D6BE06C24C0396FA18F62F74DC0C16D98E45FB424C091A6231F08114EC07D73B79BCC7E26C05BE2541492884EC0D4905C224D3726C005ABD284EC6E4EC0198B3D6BE06C24C0', 910, 910, 3323, -10.7501999999999995, -60.4547999999999988, 'S 10 45 00', 'O 60 27 17', 172, 112);
INSERT INTO bdc.mux_grid VALUES ('172/113', '0106000020E610000001000000010300000001000000050000002C82DC9796884EC02BF5386F4A3726C0FE2D81DD10114EC04BFAEA60C77E26C0D071747CD12A4EC0644D6CCD224928C0FEC5CF3657A24EC04348BADBA50128C02C82DC9796884EC02BF5386F4A3726C0', 911, 911, 3324, -11.6454000000000004, -60.6557999999999993, 'S 11 38 43', 'O 60 39 20', 172, 113);
INSERT INTO bdc.mux_grid VALUES ('172/114', '0106000020E610000001000000010300000001000000050000000E2A51255CA24EC0C4D99AE8A20128C05CBB9C07DB2A4EC02AA022181D4928C09ADD7C29B9444EC07FF4F8CA65132AC04C4C31473ABC4EC0192E719BEBCB29C00E2A51255CA24EC0C4D99AE8A20128C0', 912, 912, 3326, -12.5404999999999998, -60.8577000000000012, 'S 12 32 25', 'O 60 51 27', 172, 114);
INSERT INTO bdc.mux_grid VALUES ('172/115', '0106000020E61000000100000001030000000100000005000000D05C28A33FBC4EC06B94D966E8CB29C0440E4186C3444EC07C8350985F132AC07163E3ADC15E4EC0B5F2952094DD2BC0FFB1CACA3DD64EC0A5031FEF1C962BC0D05C28A33FBC4EC06B94D966E8CB29C0', 913, 913, 3327, -13.4354999999999993, -61.0604999999999976, 'S 13 26 07', 'O 61 03 37', 172, 115);
INSERT INTO bdc.mux_grid VALUES ('172/116', '0106000020E610000001000000010300000001000000050000008709F19643D64EC08EFF6D7719962BC07B188BE1CC5E4EC05D52666D8DDD2BC04B8995A2ED784EC0C6471B58ACA72DC0597AFB5764F04EC0F6F4226238602DC08709F19643D64EC08EFF6D7719962BC0', 914, 914, 3328, -14.3302999999999994, -61.2642999999999986, 'S 14 19 49', 'O 61 15 51', 172, 116);
INSERT INTO bdc.mux_grid VALUES ('172/117', '0106000020E61000000100000001030000000100000005000000766F4B976AF04EC04D8F90A534602DC078B1E4B2F9784EC040B1F120A5A72DC0A8BB57B33F934EC00A63B5F8AC712FC0A679BE97B00A4FC01541547D3C2A2FC0766F4B976AF04EC04D8F90A534602DC0', 915, 915, 3329, -15.2249999999999996, -61.4692999999999969, 'S 15 13 29', 'O 61 28 09', 172, 117);
INSERT INTO bdc.mux_grid VALUES ('172/118', '0106000020E610000001000000010300000001000000050000003F7A764DB70A4FC0C0C8EF79382A2FC0250E95A64C934EC065D6D039A5712FC05FB56AA0BAAD4EC0E7534943CA9D30C077214C4725254FC016CD58E3137A30C03F7A764DB70A4FC0C0C8EF79382A2FC0', 916, 916, 3332, -16.1193999999999988, -61.6754999999999995, 'S 16 07 09', 'O 61 40 31', 172, 118);
INSERT INTO bdc.mux_grid VALUES ('172/119', '0106000020E61000000100000001030000000100000005000000566AF2762C254FC080B52FBD117A30C020D3667DC8AD4EC018D4EF1DC69D30C0CFAB484061C84EC0836044C1B08231C00643D439C53F4FC0EB418460FC5E31C0566AF2762C254FC080B52FBD117A30C0', 917, 917, 3333, -17.0137, -61.8828999999999994, 'S 17 00 49', 'O 61 52 58', 172, 119);
INSERT INTO bdc.mux_grid VALUES ('172/120', '0106000020E61000000100000001030000000100000005000000B2F43AE7CC3F4FC0D3CABF14FA5E31C075F9650E70C84EC04651CE53AC8231C035A67C8136E34EC03C7FD834896732C072A1515A935A4FC0C9F8C9F5D64332C0B2F43AE7CC3F4FC0D3CABF14FA5E31C0', 918, 918, 3334, -17.9076999999999984, -62.0917999999999992, 'S 17 54 27', 'O 62 05 30', 172, 120);
INSERT INTO bdc.mux_grid VALUES ('172/121', '0106000020E61000000100000001030000000100000005000000DE409B899B5A4FC05F932D83D44332C0FEEDB74846E34EC0305EE27C846732C0449B966C3DFE4EC0FD6B7DDA524C33C024EE79AD92754FC02BA1C8E0A22833C0DE409B899B5A4FC05F932D83D44332C0', 919, 919, 3335, -18.8016000000000005, -62.3021000000000029, 'S 18 48 05', 'O 62 18 07', 172, 121);
INSERT INTO bdc.mux_grid VALUES ('172/122', '0106000020E6100000010000000103000000010000000500000045541E639B754FC0023AFE45A02833C0138990354EFE4EC03BB472D54D4C33C0882E3F2679194FC0DDDE59EC0C3134C0B9F9CC53C6904FC0A264E55C5F0D34C045541E639B754FC0023AFE45A02833C0', 920, 920, 3337, -19.6951000000000001, -62.5138999999999996, 'S 19 41 42', 'O 62 30 50', 172, 122);
INSERT INTO bdc.mux_grid VALUES ('172/123', '0106000020E6100000010000000103000000010000000500000091C29E94CF904FC0B0C37B985C0D34C019B646FA8A194FC0C6EC7197073134C0A9236EF1EC344FC0CF8E01A2B61535C02230C68B31AC4FC0B7650BA30BF234C091C29E94CF904FC0B0C37B985C0D34C0', 921, 921, 3338, -20.5884999999999998, -62.7274000000000029, 'S 20 35 18', 'O 62 43 38', 172, 123);
INSERT INTO bdc.mux_grid VALUES ('172/124', '0106000020E6100000010000000103000000010000000500000061AFF85C3BAC4FC0656674B308F234C000ED8BDAFF344FC08B353CFAB01535C014F5C6319C504FC07ACB2C304FFA35C074B733B4D7C74FC054FC64E9A6D635C061AFF85C3BAC4FC0656674B308F234C0', 922, 922, 3339, -21.4816000000000003, -62.9427000000000021, 'S 21 28 53', 'O 62 56 33', 172, 124);
INSERT INTO bdc.mux_grid VALUES ('172/125', '0106000020E610000001000000010300000001000000050000003582611BE2C74FC0EE98F3CCA3D635C0DDE0C93AB0504FC099964E3249FA35C051411F6E8A6C4FC0031869C8D5DE36C0A8E2B64EBCE34FC0571A0E6330BB36C03582611BE2C74FC0EE98F3CCA3D635C0', 923, 923, 3340, -22.3744000000000014, -63.1597999999999971, 'S 22 22 27', 'O 63 09 35', 172, 125);
INSERT INTO bdc.mux_grid VALUES ('172/126', '0106000020E6100000010000000103000000010000000500000082FBE851C7E34FC0F846F4172DBB36C0D825AAA29F6C4FC0C32FF770CFDE36C0832B3353BB884FC07011C29849C337C02B017202E3FF4FC0A528BF3FA79F37C082FBE851C7E34FC0F846F4172DBB36C0', 924, 924, 3343, -23.2669999999999995, -63.3789000000000016, 'S 23 16 01', 'O 63 22 43', 172, 126);
INSERT INTO bdc.mux_grid VALUES ('172/127', '0106000020E6100000010000000103000000010000000500000045BA27A8EEFF4FC0B4770BC4A39F37C063E2CBBFD1884FC043BAFDE342C337C0EA2B8CB632A54FC0C7F961CBA9A738C0E40174CF270E50C034B76FAB0A8438C045BA27A8EEFF4FC0B4770BC4A39F37C0', 925, 925, 3344, -24.1593000000000018, -63.6000000000000014, 'S 24 09 33', 'O 63 36 00', 172, 127);
INSERT INTO bdc.mux_grid VALUES ('172/128', '0106000020E61000000100000001030000000100000005000000FCCF0FF72D0E50C0B4C40AFD068438C0F31AAC684AA54FC06FA243B5A2A738C018509F99F4C14FC0C2122986F58B39C08C6A890F831C50C00835F0CD596839C0FCCF0FF72D0E50C0B4C40AFD068438C0', 926, 926, 3345, -25.0512000000000015, -63.8233999999999995, 'S 25 03 04', 'O 63 49 24', 172, 128);
INSERT INTO bdc.mux_grid VALUES ('172/129', '0106000020E61000000100000001030000000100000005000000B484A98F891C50C0DCCE99EA556839C0BF89C59F0DC24FC08DE85A0AEE8B39C02B5E282D05DF4FC0D4EF3AEA2B703AC0E9EE5A56052B50C026D679CA934C3AC0B484A98F891C50C0DCCE99EA556839C0', 927, 927, 3347, -25.9429000000000016, -64.0490999999999957, 'S 25 56 34', 'O 64 02 56', 172, 129);
INSERT INTO bdc.mux_grid VALUES ('172/130', '0106000020E610000001000000010300000001000000050000006A1E0C330C2B50C065DEC5AF8F4C3AC0AE8EED961FDF4FC020E9120424703AC0DBF6C7D468FC4FC0FCBE80134C543BC08052F9D1B03950C042B433BFB7303BC06A1E0C330C2B50C065DEC5AF8F4C3AC0', 928, 928, 3348, -26.8341999999999992, -64.2772999999999968, 'S 26 50 03', 'O 64 16 38', 172, 130);
INSERT INTO bdc.mux_grid VALUES ('172/131', '0106000020E61000000100000001030000000100000005000000028B970FB83950C064B3866AB3303BC04F42F4B284FC4FC00211FABD43543BC046B37515120D50C078891F1855383CC0221D93CB874850C0DA2BACC4C4143CC0028B970FB83950C064B3866AB3303BC0', 929, 929, 3349, -27.7251000000000012, -64.5079999999999956, 'S 27 43 30', 'O 64 30 28', 172, 131);
INSERT INTO bdc.mux_grid VALUES ('172/132', '0106000020E610000001000000010300000001000000050000004ECCCF6E8F4850C0618A3733C0143CC0F63CC7C7200D50C0D275D34D4C383CC048D382021E1C50C0372BE107461C3DC0A0628BA98C5750C0C73F45EDB9F83CC04ECCCF6E8F4850C0618A3733C0143CC0', 930, 930, 3350, -28.6157000000000004, -64.741500000000002, 'S 28 36 56', 'O 64 44 29', 172, 132);
INSERT INTO bdc.mux_grid VALUES ('172/133', '0106000020E61000000100000001030000000100000005000000CE5F74B7945750C04020031CB5F83CC0F296C8812D1C50C00D16FFC23C1C3DC0EFE810BC5A2B50C0EBBA8EEB1D003EC0CAB1BCF1C16650C01CC5924496DC3DC0CE5F74B7945750C04020031CB5F83CC0', 931, 931, 3352, -29.5060000000000002, -64.9779000000000053, 'S 29 30 21', 'O 64 58 40', 172, 133);
INSERT INTO bdc.mux_grid VALUES ('172/134', '0106000020E61000000100000001030000000100000005000000E6E6C36FCA6650C0306F413091DC3DC03E4FC3126B2B50C03B73D32514003EC09428ECEECA3A50C058EC3AC4DBE33EC03CC0EC4B2A7650C04AE8A8CE58C03EC0E6E6C36FCA6650C0306F413091DC3DC0', 932, 932, 3353, -30.3958000000000013, -65.2173999999999978, 'S 30 23 44', 'O 65 13 02', 172, 134);
INSERT INTO bdc.mux_grid VALUES ('172/135', '0106000020E610000001000000010300000001000000050000009098F03F337650C09EBDC57353C03EC0AA3C5328DC3A50C0B810E776D1E33EC03284D86C714A50C066CA7A8A7EC73FC018E07584C88550C04C77598700A43FC09098F03F337650C09EBDC57353C03EC0', 933, 933, 3355, -31.2852999999999994, -65.4599999999999937, 'S 31 17 06', 'O 65 27 36', 172, 135);
INSERT INTO bdc.mux_grid VALUES ('172/136', '0106000020E61000000100000001030000000100000005000000949BCAF4D18550C0985F1BE2FAA33FC050AC1D95834A50C07F2F48AE73C73FC0D8037F2F515A50C01878C596825540C01EF32B8F9F9550C02410AF30C64340C0949BCAF4D18550C0985F1BE2FAA33FC0', 934, 934, 3356, -32.1743000000000023, -65.7061000000000064, 'S 32 10 27', 'O 65 42 21', 172, 136);
INSERT INTO bdc.mux_grid VALUES ('172/137', '0106000020E6100000010000000103000000010000000500000048F0A582A99550C0FBB0D736C34340C0B293C053645A50C0027650DD7C5540C042D09D5B6D6A50C050A12F4937C740C0D22C838AB2A550C04ADCB6A27DB540C048F0A582A99550C0FBB0D736C34340C0', 935, 935, 3357, -33.0628999999999991, -65.9556999999999931, 'S 33 03 46', 'O 65 57 20', 172, 137);
INSERT INTO bdc.mux_grid VALUES ('172/138', '0106000020E6100000010000000103000000010000000500000056518208BDA550C0F292727F7AB540C0C4AB048A816A50C0E0DD224031C740C09C238244C97A50C0D2694DC9DC3841C02CC9FFC204B650C0E41E9D08262741C056518208BDA550C0F292727F7AB540C0', 936, 936, 3358, -33.9510000000000005, -66.2091000000000065, 'S 33 57 03', 'O 66 12 32', 172, 138);
INSERT INTO bdc.mux_grid VALUES ('172/139', '0106000020E610000001000000010300000001000000050000009C1F7CD30FB650C092D489B9222741C040B2598CDE7A50C0F4F6156CD63841C0983AD46F688B50C02FB4B67D72AA41C0F6A7F6B699C650C0CA912ACBBE9841C09C1F7CD30FB650C092D489B9222741C0', 937, 937, 3360, -34.8387000000000029, -66.4664999999999964, 'S 34 50 19', 'O 66 27 59', 172, 139);
INSERT INTO bdc.mux_grid VALUES ('172/140', '0106000020E61000000100000001030000000100000005000000F0618E62A5C650C0407FB44DBB9841C0CAF0A4E17E8B50C0DAD262C76BAA41C0585BBE994E9C50C030D829C6F71B42C07ECCA71A75D750C096847B4C470A42C0F0618E62A5C650C0407FB44DBB9841C0', 938, 938, 3361, -35.7257999999999996, -66.7280999999999977, 'S 35 43 33', 'O 66 43 41', 172, 140);
INSERT INTO bdc.mux_grid VALUES ('172/141', '0106000020E610000001000000010300000001000000050000009CCEAE6A81D750C0F48BD89D430A42C0B82C6B47669C50C0042A60B1F01B42C0B63279B97FAD50C04679DBFA6B8D42C09CD4BCDC9AE850C036DB53E7BE7B42C09CCEAE6A81D750C0F48BD89D430A42C0', 939, 939, 3362, -36.6124999999999972, -66.9941000000000031, 'S 36 36 45', 'O 66 59 38', 172, 141);
INSERT INTO bdc.mux_grid VALUES ('172/142', '0106000020E6100000010000000103000000010000000500000002044EDBA7E850C04A5B7E04BB7B42C0104A60B698AD50C0AA37D181648D42C0B814490600BF50C04639B46BCEFE42C0AACE362B0FFA50C0E65C61EE24ED42C002044EDBA7E850C04A5B7E04BB7B42C0', 940, 940, 3363, -37.4986000000000033, -67.2647999999999939, 'S 37 29 55', 'O 67 15 53', 172, 142);
INSERT INTO bdc.mux_grid VALUES ('172/143', '0106000020E61000000100000001030000000100000005000000725247E31CFA50C0FA6E12D420ED42C0EC3468671ABF50C04E542288C6FE42C09A28F9FCD3D050C04E3C7A5F1E7043C01E46D878D60B51C0FA566AAB785E43C0725247E31CFA50C0FA6E12D420ED42C0', 941, 941, 3364, -38.3841999999999999, -67.5404999999999944, 'S 38 23 03', 'O 67 32 25', 172, 143);
INSERT INTO bdc.mux_grid VALUES ('172/144', '0106000020E6100000010000000103000000010000000500000057024DF6E40B51C04C621356745E43C0B43716D9EFD050C0C83A910A167043C0EA4BE36500E350C0B40AE4125BE143C08C161A83F51D51C03A32665EB9CF43C057024DF6E40B51C04C621356745E43C0', 942, 942, 3366, -39.2691999999999979, -67.821399999999997, 'S 39 16 09', 'O 67 49 16', 172, 144);
INSERT INTO bdc.mux_grid VALUES ('172/145', '0106000020E61000000100000001030000000100000005000000AAABDFD2041E51C0CCBE29CAB4CF43C0F08AB9D51DE350C05D843E4552E143C0F866955B8AF550C0A22F92B7835244C0B087BB58713051C0126A7D3CE64044C0AAABDFD2041E51C0CCBE29CAB4CF43C0', 943, 943, 3367, -40.1535999999999973, -68.1077999999999975, 'S 40 09 13', 'O 68 06 28', 172, 145);
INSERT INTO bdc.mux_grid VALUES ('172/146', '0106000020E610000001000000010300000001000000050000004C25E188813051C00C1B2765E14044C0B2F4077AA9F550C008B225697A5244C064362752770851C05476EC7297C344C0FE6600614F4351C058DFED6EFEB144C04C25E188813051C00C1B2765E14044C0', 944, 944, 3368, -41.0373999999999981, -68.4000999999999948, 'S 41 02 14', 'O 68 24 00', 172, 146);
INSERT INTO bdc.mux_grid VALUES ('172/147', '0106000020E6100000010000000103000000010000000500000062E0D580604351C02E74E94FF9B144C01C94793C980851C0F29DF89A8DC344C08A31561FCD1B51C08A49DF5C953445C0D07DB263955651C0C61FD011012345C062E0D580604351C02E74E94FF9B144C0', 945, 945, 3369, -41.9206000000000003, -68.698599999999999, 'S 41 55 14', 'O 68 41 54', 172, 147);
INSERT INTO bdc.mux_grid VALUES ('172/148', '0106000020E61000000100000001030000000100000005000000C603EA83A75651C0345E1FA6FB2245C010956BF5EF1B51C0FED1DAF18A3445C094348003922F51C07E2E757E7CA545C04AA3FE91496A51C0B4BAB932ED9345C0C603EA83A75651C0345E1FA6FB2245C0', 946, 946, 3370, -42.8029999999999973, -69.0036000000000058, 'S 42 48 10', 'O 69 00 13', 172, 148);
INSERT INTO bdc.mux_grid VALUES ('172/149', '0106000020E6100000010000000103000000010000000500000078B1D2C45C6A51C00E17E974E79345C06A9C22E8B62F51C0DCB0F87571A545C0B02199B3CC4351C0F5BB47D04B1646C0BC364990727E51C0282238CFC10446C078B1D2C45C6A51C00E17E974E79345C0', 947, 947, 3371, -43.6848000000000027, -69.3156000000000034, 'S 43 41 05', 'O 69 18 56', 172, 149);
INSERT INTO bdc.mux_grid VALUES ('172/150', '0106000020E610000001000000010300000001000000050000000046A7E9867E51C09CFA51B9BB0446C05A34C9CCF34351C0DDCBF51E401646C086B03B64845851C0D0D0C238028746C02CC21981179351C08EFF1ED37D7546C00046A7E9867E51C09CFA51B9BB0446C0', 948, 948, 3372, -44.565800000000003, -69.6350000000000051, 'S 44 33 56', 'O 69 38 06', 172, 150);
INSERT INTO bdc.mux_grid VALUES ('172/151', '0106000020E610000001000000010300000001000000050000004670D2162D9351C068359D5E777546C0BAB08ADBAD5851C0AC152DD2F58646C0456FFAD5C06D51C014DF338A9EF746C0D02E421140A851C0D0FEA31620E646C04670D2162D9351C068359D5E777546C0', 949, 949, 3373, -45.4461000000000013, -69.9621999999999957, 'S 45 26 45', 'O 69 57 44', 172, 151);
INSERT INTO bdc.mux_grid VALUES ('172/152', '0106000020E610000001000000010300000001000000050000001CAB3FFB56A851C0D5AF5F3C19E646C05CADEFD8EC6D51C0C4BDBC6091F746C0826D1B638A8351C0BF539E801F6847C0426B6B85F4BD51C0CE45415CA75647C01CAB3FFB56A851C0D5AF5F3C19E646C0', 950, 950, 3374, -46.3254999999999981, -70.2977999999999952, 'S 46 19 31', 'O 70 17 52', 172, 152);
INSERT INTO bdc.mux_grid VALUES ('172/153', '0106000020E610000001000000010300000001000000050000007C0CEFDD0CBE51C057616014A05647C02EDFA623B98351C084A95685116847C09278EF0EEA9951C0ACEB4CBF83D847C0E0A537C93DD451C07EA3564E12C747C07C0CEFDD0CBE51C057616014A05647C0', 951, 951, 3376, -47.2040999999999968, -70.6422000000000025, 'S 47 12 14', 'O 70 38 31', 172, 153);
INSERT INTO bdc.mux_grid VALUES ('172/154', '0106000020E610000001000000010300000001000000050000006CCA1FAD57D451C0DA0437900AC747C0506EEBC31B9A51C0D643CDE174D847C06065FD96E9B051C0AC9116CEC94848C07AC1318025EB51C0AE52807C5F3748C06CCA1FAD57D451C0DA0437900AC747C0', 952, 952, 3378, -48.0818000000000012, -70.9959999999999951, 'S 48 04 54', 'O 70 59 45', 172, 154);
INSERT INTO bdc.mux_grid VALUES ('172/155', '0106000020E61000000100000001030000000100000005000000202F490F41EB51C06A04A03E573748C09C92C17C1EB151C0122D53FCB94848C06A9B428693C851C090BC4B16F0B848C0EC37CA18B60252C0EA9398588DA748C0202F490F41EB51C06A04A03E573748C0', 953, 953, 3379, -48.9585000000000008, -71.3598999999999961, 'S 48 57 30', 'O 71 21 35', 172, 155);
INSERT INTO bdc.mux_grid VALUES ('172/156', '0106000020E6100000010000000103000000010000000500000022802276D30252C078C77A9084A748C01A1A4BDFCBC851C0249F623CDFB848C0CA89D44AF3E051C03A8C3FDFF42849C0D4EFABE1FA1A52C090B457339A1749C022802276D30252C078C77A9084A748C0', 954, 954, 3380, -49.8342999999999989, -71.734499999999997, 'S 49 50 03', 'O 71 44 04', 172, 156);
INSERT INTO bdc.mux_grid VALUES ('172/157', '0106000020E610000001000000010300000001000000050000007C8B04341A1B52C088EC65D5901749C092DE7F602FE151C0B2A93FE7E22849C010C83A4E15FA51C0ECAD5D4AD69849C0FC74BF21003452C0C2F08338848749C07C8B04341A1B52C088EC65D5901749C0', 955, 955, 3382, -50.7090000000000032, -72.1205000000000069, 'S 50 42 32', 'O 72 07 13', 172, 157);
INSERT INTO bdc.mux_grid VALUES ('172/94', '0106000020E61000000100000001030000000100000005000000457C191E46A94CC003698975FAA717409DC0ED64AB314CC03E42A374E7181740235649C7E54A4CC0CC89A4D081831340CB11758080C24CC091B08AD194121440457C191E46A94CC003698975FAA71740', 956, 956, 3407, 5.37619999999999987, -56.9087999999999994, 'N 05 22 34', 'O 56 54 31', 172, 94);
INSERT INTO bdc.mux_grid VALUES ('172/95', '0106000020E610000001000000010300000001000000050000007BC017417EC24CC0612846219212144046DFE39DE14A4CC0EA4C2FD67C8313405D9EF6C30F644CC031E6AA3B0EDC0F40917F2A67ACDB4CC0904EEC681C7D10407BC017417EC24CC06128462192121440', 957, 957, 3408, 4.48029999999999973, -57.1056000000000026, 'N 04 28 49', 'O 57 06 20', 172, 95);
INSERT INTO bdc.mux_grid VALUES ('172/96', '0106000020E61000000100000001030000000100000005000000E5F29687AADB4CC08F6C3D2B1A7D1040717AE5500C644CC08390F7FA05DC0F405764FB63307D4CC08A993A0400B10840CADCAC9ACEF44CC028E2BD5F2ECF0940E5F29687AADB4CC08F6C3D2B1A7D1040', 958, 958, 3409, 3.58429999999999982, -57.3021000000000029, 'N 03 35 03', 'O 57 18 07', 172, 96);
INSERT INTO bdc.mux_grid VALUES ('172/97', '0106000020E610000001000000010300000001000000050000000B32FD19CDF44CC0B26C65C72ACF0940D70897A52D7D4CC00A1AC973F9B00840320107CA49964CC0C6641597DE850140662A6D3EE90D4DC06DB7B1EA0FA402400B32FD19CDF44CC0B26C65C72ACF0940', 959, 959, 3410, 2.68829999999999991, -57.4983000000000004, 'N 02 41 17', 'O 57 29 53', 172, 97);
INSERT INTO bdc.mux_grid VALUES ('172/98', '0106000020E61000000100000001030000000100000005000000AF93E91BE80D4DC0FCD1A6330DA40240EB96FFBE47964CC0673FC2B3D9850140D0933C155EAF4CC0EF12141E5FB5F43F95902672FE264DC01938DD1DC6F1F63FAF93E91BE80D4DC0FCD1A6330DA40240', 960, 960, 3412, 1.79220000000000002, -57.6944000000000017, 'N 01 47 31', 'O 57 41 39', 172, 98);
INSERT INTO bdc.mux_grid VALUES ('172/99', '0106000020E61000000100000001030000000100000005000000D79744ADFD264DC0E606CC6FC2F1F63FD99F98BC5CAF4CC0A0BE00AD58B5F43FF3D43E626FC84CC0913A4E30C47BD93FF1CCEA5210404DC0D4ADBD9DB536E13FD79744ADFD264DC0E606CC6FC2F1F63F', 961, 961, 3413, 0.896100000000000008, -57.8903000000000034, 'N 00 53 45', 'O 57 53 24', 172, 99);
INSERT INTO bdc.mux_grid VALUES ('173/100', '0106000020E61000000100000001030000000100000005000000582DF2DE99BB4DC0FA0D24BEB136E13FBAA1FFAEF8434DC028AD07B6B77BD93F25BFDEBF095D4DC01B59525307DEDFBFC14AD1EFAAD44DC04FEA118D5BECD6BF582DF2DE99BB4DC0FA0D24BEB136E13F', 962, 962, 3414, 0, -59.0512000000000015, 'N 00 00 00', 'O 59 03 04', 173, 100);
INSERT INTO bdc.mux_grid VALUES ('173/101', '0106000020E6100000010000000103000000010000000500000095F245E5AAD44DC06A75E2565CECD6BF4F176ACA095D4DC00CCE818906DEDFBF77AF8D611B764DC06CFDAB51EE4DF6BFC08A697CBCED4DC0402704C58311F4BF95F245E5AAD44DC06A75E2565CECD6BF', 963, 963, 3417, -0.896100000000000008, -59.2471000000000032, 'S 00 53 45', 'O 59 14 49', 173, 101);
INSERT INTO bdc.mux_grid VALUES ('173/102', '0106000020E61000000100000001030000000100000005000000F7D6EBCEBCED4DC098BC373A8211F4BF0CFB8D1D1C764DC0F1251ACEEA4DF6BFB11F4556308F4DC0F95A579B245202C09EFBA207D1064EC04D266651F03301C0F7D6EBCEBCED4DC098BC373A8211F4BF', 964, 964, 3418, -1.79220000000000002, -59.4429999999999978, 'S 01 47 31', 'O 59 26 34', 173, 102);
INSERT INTO bdc.mux_grid VALUES ('173/103', '0106000020E6100000010000000103000000010000000500000061145AB7D1064EC0D1FB01ADEE3301C0A2CA13C4318F4DC0D0A42930215202C0ADEFF8BA4AA84DC023F83AA7437D09C06D393FAEEA1F4EC0254F1324115F08C061145AB7D1064EC0D1FB01ADEE3301C0', 965, 965, 3419, -2.68829999999999991, -59.6390000000000029, 'S 02 41 17', 'O 59 38 20', 173, 103);
INSERT INTO bdc.mux_grid VALUES ('173/104', '0106000020E6100000010000000103000000010000000500000017A27EBBEB1F4EC06062E99F0E5F08C0C32C44DB4CA84DC06EB407913E7D09C04C6046AF6CC14DC0A0F04658275410C0A0D5808F0B394EC0328F6FBF1E8A0FC017A27EBBEB1F4EC06062E99F0E5F08C0', 966, 966, 3420, -3.58429999999999982, -59.8352999999999966, 'S 03 35 03', 'O 59 50 06', 173, 104);
INSERT INTO bdc.mux_grid VALUES ('173/105', '0106000020E6100000010000000103000000010000000500000063C2C8FA0C394EC023274D5A1B8A0FC0F8D911836FC14DC055E973F6235410C0F662805698DA4DC07BBDD50CA0E913C05F4B37CE35524EC0B76788C3895A13C063C2C8FA0C394EC023274D5A1B8A0FC0', 967, 967, 3422, -4.48029999999999973, -60.0317000000000007, 'S 04 28 49', 'O 60 01 54', 173, 105);
INSERT INTO bdc.mux_grid VALUES ('173/106', '0106000020E61000000100000001030000000100000005000000ED24359837524EC03986AB9F875A13C0F84426DF9BDA4DC03B37ABD29BE913C06ABEBFD8CFF34DC0A1E66221097F17C05D9ECE916B6B4EC0A03563EEF4EF16C0ED24359837524EC03986AB9F875A13C0', 968, 968, 3423, -5.37619999999999987, -60.2286000000000001, 'S 05 22 34', 'O 60 13 42', 173, 106);
INSERT INTO bdc.mux_grid VALUES ('173/107', '0106000020E6100000010000000103000000010000000500000069B55DBB6D6B4EC0C04C3458F2EF16C06817F217D4F34DC01AA6D90C047F17C0E123F863150D4EC0AB5CB3C45F141BC0E3C16307AF844EC051030E104E851AC069B55DBB6D6B4EC0C04C3458F2EF16C0', 969, 969, 3424, -6.27210000000000001, -60.4258000000000024, 'S 06 16 19', 'O 60 25 32', 173, 107);
INSERT INTO bdc.mux_grid VALUES ('173/108', '0106000020E610000001000000010300000001000000050000001F318E91B1844EC0BAC04E064B851AC003A4C25B1A0D4EC071EE58D359141BC07E5D132D6B264EC00C28F423A1A91EC09CEADE62029E4EC054FAE956921A1EC01F318E91B1844EC0BAC04E064B851AC0', 970, 970, 3425, -7.16790000000000038, -60.6233999999999966, 'S 07 10 04', 'O 60 37 24', 173, 108);
INSERT INTO bdc.mux_grid VALUES ('173/109', '0106000020E6100000010000000103000000010000000500000025ACDE4E059E4EC068C722D88E1A1EC0C272DDDF70264EC0405AE8529AA91EC005C51371D33F4EC030B23835651F21C068FE14E067B74EC0C4E8D577DFD720C025ACDE4E059E4EC068C722D88E1A1EC0', 971, 971, 3427, -8.06359999999999921, -60.8215999999999966, 'S 08 03 49', 'O 60 49 17', 173, 109);
INSERT INTO bdc.mux_grid VALUES ('173/110', '0106000020E61000000100000001030000000100000005000000AE33552F6BB74EC08D25157DDDD720C0931AA3E1D93F4EC0F4A4315B611F21C060423F7650594EC08F8DA360ECE922C07B5BF1C3E1D04EC0280E878268A222C0AE33552F6BB74EC08D25157DDDD720C0', 972, 972, 3428, -8.95919999999999916, -61.0204000000000022, 'S 08 57 33', 'O 61 01 13', 173, 110);
INSERT INTO bdc.mux_grid VALUES ('173/111', '0106000020E610000001000000010300000001000000050000008ECB0F78E5D04EC0AAA4714B66A222C02EA7BAA757594EC0A7C93813E8E922C0781F548DE4724EC0E88D85A764B424C0D843A95D72EA4EC0EC68BEDFE26C24C08ECB0F78E5D04EC0AAA4714B66A222C0', 973, 973, 3429, -9.85479999999999912, -61.2197999999999993, 'S 09 51 17', 'O 61 13 11', 173, 111);
INSERT INTO bdc.mux_grid VALUES ('173/112', '0106000020E610000001000000010300000001000000050000008512787876EA4EC01D8B3D6BE06C24C0FED64683EC724EC09B6D98E45FB424C0550EC912928C4EC03973B79BCC7E26C0DB49FA071C044FC0BA905C224D3726C08512787876EA4EC01D8B3D6BE06C24C0', 974, 974, 3430, -10.7501999999999995, -61.4200000000000017, 'S 10 45 00', 'O 61 25 11', 173, 112);
INSERT INTO bdc.mux_grid VALUES ('173/113', '0106000020E61000000100000001030000000100000005000000CAE9818B20044FC0FCF4386F4A3726C09B9526D19A8C4EC01CFAEA60C77E26C072D919705BA64EC0984D6CCD224928C0A22D752AE11D4FC07948BADBA50128C0CAE9818B20044FC0FCF4386F4A3726C0', 975, 975, 3432, -11.6454000000000004, -61.6210000000000022, 'S 11 38 43', 'O 61 37 15', 173, 113);
INSERT INTO bdc.mux_grid VALUES ('173/114', '0106000020E61000000100000001030000000100000005000000A091F618E61D4FC004DA9AE8A20128C0102342FB64A64EC054A022181D4928C04E45221D43C04EC08DF4F8CA65132AC0DEB3D63AC4374FC03E2E719BEBCB29C0A091F618E61D4FC004DA9AE8A20128C0', 976, 976, 3433, -12.5404999999999998, -61.8228000000000009, 'S 12 32 25', 'O 61 49 22', 173, 114);
INSERT INTO bdc.mux_grid VALUES ('173/115', '0106000020E6100000010000000103000000010000000500000056C4CD96C9374FC09594D966E8CB29C0EC75E6794DC04EC0908350985F132AC020CB88A14BDA4EC02DF3952094DD2BC0891970BEC7514FC031041FEF1C962BC056C4CD96C9374FC09594D966E8CB29C0', 977, 977, 3434, -13.4354999999999993, -62.0255999999999972, 'S 13 26 07', 'O 62 01 32', 173, 115);
INSERT INTO bdc.mux_grid VALUES ('173/116', '0106000020E610000001000000010300000001000000050000005371968ACD514FC0F3FF6D7719962BC0208030D556DA4EC0D652666D8DDD2BC0EEF03A9677F44EC023481B58ACA72DC021E2A04BEE6B4FC041F5226238602DC05371968ACD514FC0F3FF6D7719962BC0', 978, 978, 3435, -14.3302999999999994, -62.2295000000000016, 'S 14 19 49', 'O 62 13 46', 173, 116);
INSERT INTO bdc.mux_grid VALUES ('173/117', '0106000020E6100000010000000103000000010000000500000014D7F08AF46B4FC0AF8F90A534602DC05C198AA683F44EC077B1F120A5A72DC08B23FDA6C90E4FC02363B5F8AC712FC043E1638B3A864FC05B41547D3C2A2FC014D7F08AF46B4FC0AF8F90A534602DC0', 979, 979, 3436, -15.2249999999999996, -62.4344999999999999, 'S 15 13 29', 'O 62 26 04', 173, 117);
INSERT INTO bdc.mux_grid VALUES ('173/118', '0106000020E61000000100000001030000000100000005000000DFE11B4141864FC000C9EF79382A2FC0E9753A9AD60E4FC090D6D039A5712FC01A1D109444294FC0B2534943CA9D30C01089F13AAFA04FC0EBCC58E3137A30C0DFE11B4141864FC000C9EF79382A2FC0', 980, 980, 3438, -16.1193999999999988, -62.6405999999999992, 'S 16 07 09', 'O 62 38 26', 173, 118);
INSERT INTO bdc.mux_grid VALUES ('173/119', '0106000020E61000000100000001030000000100000005000000E1D1976AB6A04FC05AB52FBD117A30C0CD3A0C7152294FC0E9D3EF1DC69D30C08213EE33EB434FC0846044C1B08231C098AA792D4FBB4FC0F5418460FC5E31C0E1D1976AB6A04FC05AB52FBD117A30C0', 981, 981, 3439, -17.0137, -62.8481000000000023, 'S 17 00 49', 'O 62 50 53', 173, 119);
INSERT INTO bdc.mux_grid VALUES ('173/120', '0106000020E61000000100000001030000000100000005000000365CE0DA56BB4FC0E0CABF14FA5E31C0F9600B02FA434FC05451CE53AC8231C0B90D2275C05E4FC03B7FD834896732C0F508F74D1DD64FC0C7F8C9F5D64332C0365CE0DA56BB4FC0E0CABF14FA5E31C0', 982, 982, 3440, -17.9076999999999984, -63.0568999999999988, 'S 17 54 27', 'O 63 03 24', 173, 120);
INSERT INTO bdc.mux_grid VALUES ('173/121', '0106000020E6100000010000000103000000010000000500000070A8407D25D64FC058932D83D44332C0D6555D3CD05E4FC0175EE27C846732C01A033C60C7794FC0D46B7DDA524C33C0B4551FA11CF14FC016A1C8E0A22833C070A8407D25D64FC058932D83D44332C0', 983, 983, 3442, -18.8016000000000005, -63.2672000000000025, 'S 18 48 05', 'O 63 16 01', 173, 121);
INSERT INTO bdc.mux_grid VALUES ('173/122', '0106000020E61000000100000001030000000100000005000000E5BBC35625F14FC0E639FE45A02833C0B3F03529D8794FC021B472D54D4C33C03596E41903954FC034DF59EC0C3134C0B230B923280650C0F964E55C5F0D34C0E5BBC35625F14FC0E639FE45A02833C0', 984, 984, 3443, -19.6951000000000001, -63.4791000000000025, 'S 19 41 42', 'O 63 28 44', 173, 122);
INSERT INTO bdc.mux_grid VALUES ('173/123', '0106000020E61000000100000001030000000100000005000000141522C42C0650C00DC47B985C0D34C0AF1DECED14954FC025ED7197073134C0318B13E576B04FC09F8E01A2B61535C0D4CBB5BFDD1350C086650BA30BF234C0141522C42C0650C00DC47B985C0D34C0', 985, 985, 3444, -20.5884999999999998, -63.6925999999999988, 'S 20 35 18', 'O 63 41 33', 173, 123);
INSERT INTO bdc.mux_grid VALUES ('173/124', '0106000020E61000000100000001030000000100000005000000960B4FA8E21350C01D6674B308F234C0875431CE89B04FC05A353CFAB01535C0995C6C2526CC4FC03ACB2C304FFA35C0A08FECD3B02150C0FDFB64E9A6D635C0960B4FA8E21350C01D6674B308F234C0', 986, 986, 3445, -21.4816000000000003, -63.9078000000000017, 'S 21 28 53', 'O 63 54 28', 173, 124);
INSERT INTO bdc.mux_grid VALUES ('173/125', '0106000020E61000000100000001030000000100000005000000D0748307B62150C0B598F3CCA3D635C0D3486F2E3ACC4FC037964E3249FA35C053A9C46114E84FC0121869C8D5DE36C010252E21A32F50C08F1A0E6330BB36C0D0748307B62150C0B598F3CCA3D635C0', 987, 987, 3447, -22.3744000000000014, -64.1248999999999967, 'S 22 22 27', 'O 64 07 29', 173, 125);
INSERT INTO bdc.mux_grid VALUES ('173/126', '0106000020E610000001000000010300000001000000050000009631C7A2A82F50C01F47F4172DBB36C06A8D4F9629E84FC0F32FF770CFDE36C088496CA3220250C09311C29849C337C06CB40B7BB63D50C0BD28BF3FA79F37C09631C7A2A82F50C01F47F4172DBB36C0', 988, 988, 3449, -23.2669999999999995, -64.3439999999999941, 'S 23 16 01', 'O 64 20 38', 173, 126);
INSERT INTO bdc.mux_grid VALUES ('173/127', '0106000020E610000001000000010300000001000000050000000E91E64DBC3D50C0BD770BC4A39F37C01CA5B8D92D0250C04EBAFDE342C337C0DDC918555E1050C0A4F961CBA9A738C0CEB546C9EC4B50C012B76FAB0A8438C00E91E64DBC3D50C0BD770BC4A39F37C0', 989, 989, 3450, -24.1593000000000018, -64.5652000000000044, 'S 24 09 33', 'O 64 33 54', 173, 127);
INSERT INTO bdc.mux_grid VALUES ('173/128', '0106000020E61000000100000001030000000100000005000000DA83E2F0F24B50C097C40AFD068438C022C1282E6A1050C072A243B5A2A738C0BA5BA246BF1E50C03B132986F58B39C0721E5C09485A50C06035F0CD596839C0DA83E2F0F24B50C097C40AFD068438C0', 990, 990, 3452, -25.0512000000000015, -64.7886000000000024, 'S 25 03 04', 'O 64 47 18', 173, 128);
INSERT INTO bdc.mux_grid VALUES ('173/129', '0106000020E61000000100000001030000000100000005000000C0387C894E5A50C020CF99EA556839C0AC78B5C9CB1E50C0F7E85A0AEE8B39C0DAE26690472D50C0C9EF3AEA2B703AC0EDA22D50CA6850C0F2D579CA934C3AC0C0387C894E5A50C020CF99EA556839C0', 991, 991, 3453, -25.9429000000000016, -65.0143000000000058, 'S 25 56 34', 'O 65 00 51', 173, 129);
INSERT INTO bdc.mux_grid VALUES ('173/130', '0106000020E6100000010000000103000000010000000500000030D2DE2CD16850C055DEC5AF8F4C3AC01E7B49C5542D50C012E9120424703AC035AF3664F93B50C0E2BE80134C543BC04606CCCB757750C024B433BFB7303BC030D2DE2CD16850C055DEC5AF8F4C3AC0', 992, 992, 3454, -26.8341999999999992, -65.2424000000000035, 'S 26 50 03', 'O 65 14 32', 173, 130);
INSERT INTO bdc.mux_grid VALUES ('173/131', '0106000020E61000000100000001030000000100000005000000023F6A097D7750C022B3866AB3303BC0DCD44C53073C50C0EF10FABD43543BC00467480FD74A50C0D4891F1855383CC028D165C54C8650C0072CACC4C4143CC0023F6A097D7750C022B3866AB3303BC0', 993, 993, 3455, -27.7251000000000012, -65.4732000000000056, 'S 27 43 30', 'O 65 28 23', 173, 131);
INSERT INTO bdc.mux_grid VALUES ('173/132', '0106000020E610000001000000010300000001000000050000001280A268548650C0BA8A3733C0143CC0DEF099C1E54A50C01976D34D4C383CC0288755FCE25950C0EE2AE107461C3DC05C165EA3519550C08F3F45EDB9F83CC01280A268548650C0BA8A3733C0143CC0', 994, 994, 3457, -28.6157000000000004, -65.7066999999999979, 'S 28 36 56', 'O 65 42 24', 173, 132);
INSERT INTO bdc.mux_grid VALUES ('173/133', '0106000020E61000000100000001030000000100000005000000B21347B1599550C0F11F031CB5F83CC0B44A9B7BF25950C0D615FFC23C1C3DC0AE9CE3B51F6950C0A2BA8EEB1D003EC0AC658FEB86A450C0BDC4924496DC3DC0B21347B1599550C0F11F031CB5F83CC0', 995, 995, 3458, -29.5060000000000002, -65.9431000000000012, 'S 29 30 21', 'O 65 56 35', 173, 133);
INSERT INTO bdc.mux_grid VALUES ('173/134', '0106000020E61000000100000001030000000100000005000000CC9A96698FA450C0D16E413091DC3DC00003960C306950C0F672D32514003EC05EDCBEE88F7850C07DEC3AC4DBE33EC02A74BF45EFB350C05BE8A8CE58C03EC0CC9A96698FA450C0D16E413091DC3DC0', 996, 996, 3459, -30.3958000000000013, -66.1825000000000045, 'S 30 23 44', 'O 66 10 57', 173, 134);
INSERT INTO bdc.mux_grid VALUES ('173/135', '0106000020E61000000100000001030000000100000005000000564CC339F8B350C0C7BDC57353C03EC04EF02522A17850C0F810E776D1E33EC0CC37AB66368850C019CA7A8A7EC73FC0D493487E8DC350C0EA76598700A43FC0564CC339F8B350C0C7BDC57353C03EC0', 997, 997, 3462, -31.2852999999999994, -66.4252000000000038, 'S 31 17 06', 'O 66 25 30', 173, 135);
INSERT INTO bdc.mux_grid VALUES ('173/136', '0106000020E610000001000000010300000001000000050000000E4F9DEE96C350C0595F1BE2FAA33FC05460F08E488850C0EE2E48AE73C73FC0EEB75129169850C05078C596825540C0AAA6FE8864D350C08410AF30C64340C00E4F9DEE96C350C0595F1BE2FAA33FC0', 998, 998, 3463, -32.1743000000000023, -66.6711999999999989, 'S 32 10 27', 'O 66 40 16', 173, 136);
INSERT INTO bdc.mux_grid VALUES ('173/137', '0106000020E6100000010000000103000000010000000500000002A4787C6ED350C04CB1D736C34340C0B047934D299850C0407650DD7C5540C03A84705532A850C086A12F4937C740C08CE0558477E350C092DCB6A27DB540C002A4787C6ED350C04CB1D736C34340C0', 999, 999, 3464, -33.0628999999999991, -66.9207999999999998, 'S 33 03 46', 'O 66 55 15', 173, 137);
INSERT INTO bdc.mux_grid VALUES ('173/138', '0106000020E610000001000000010300000001000000050000000E05550282E350C03C93727F7AB540C0BE5FD78346A850C014DE224031C740C094D7543E8EB850C0006A4DC9DC3841C0E47CD2BCC9F350C0291F9D08262741C00E05550282E350C03C93727F7AB540C0', 1000, 1000, 3466, -33.9510000000000005, -67.174199999999999, 'S 33 57 03', 'O 67 10 27', 173, 138);
INSERT INTO bdc.mux_grid VALUES ('173/139', '0106000020E6100000010000000103000000010000000500000090D34ECDD4F350C0C2D489B9222741C0F4652C86A3B850C038F7156CD63841C04CEEA6692DC950C068B4B67D72AA41C0E85BC9B05E0451C0F4912ACBBE9841C090D34ECDD4F350C0C2D489B9222741C0', 1001, 1001, 3467, -34.8387000000000029, -67.4316000000000031, 'S 34 50 19', 'O 67 25 53', 173, 139);
INSERT INTO bdc.mux_grid VALUES ('173/140', '0106000020E61000000100000001030000000100000005000000B415615C6A0451C0767FB44DBB9841C088A477DB43C950C010D362C76BAA41C0260F919313DA50C0DED829C6F71B42C054807A143A1551C044857B4C470A42C0B415615C6A0451C0767FB44DBB9841C0', 1002, 1002, 3468, -35.7257999999999996, -67.6932000000000045, 'S 35 43 33', 'O 67 41 35', 173, 140);
INSERT INTO bdc.mux_grid VALUES ('173/141', '0106000020E61000000100000001030000000100000005000000A6828164461551C0948CD89D430A42C0C0E03D412BDA50C0A22A60B1F01B42C098E64BB344EB50C0DE78DBFA6B8D42C07C888FD65F2651C0D0DA53E7BE7B42C0A6828164461551C0948CD89D430A42C0', 1003, 1003, 3469, -36.6124999999999972, -67.9591999999999956, 'S 36 36 45', 'O 67 57 33', 173, 141);
INSERT INTO bdc.mux_grid VALUES ('173/142', '0106000020E6100000010000000103000000010000000500000008B820D56C2651C0DA5A7E04BB7B42C0D2FD32B05DEB50C04C37D181648D42C07AC81B00C5FC50C0E238B46BCEFE42C0B0820925D43751C0705C61EE24ED42C008B820D56C2651C0DA5A7E04BB7B42C0', 1004, 1004, 3471, -37.4986000000000033, -68.230000000000004, 'S 37 29 55', 'O 68 13 47', 173, 142);
INSERT INTO bdc.mux_grid VALUES ('173/143', '0106000020E61000000100000001030000000100000005000000FA051ADDE13751C0A66E12D420ED42C0BAE83A61DFFC50C0E6532288C6FE42C066DCCBF6980E51C0E03B7A5F1E7043C0A6F9AA729B4951C0A2566AAB785E43C0FA051ADDE13751C0A66E12D420ED42C0', 1005, 1005, 3472, -38.3841999999999999, -68.5056000000000012, 'S 38 23 03', 'O 68 30 20', 173, 143);
INSERT INTO bdc.mux_grid VALUES ('173/144', '0106000020E6100000010000000103000000010000000500000048B61FF0A94951C0D4611356745E43C060EBE8D2B40E51C0623A910A167043C0AAFFB55FC52051C0C80AE4125BE143C092CAEC7CBA5B51C03832665EB9CF43C048B61FF0A94951C0D4611356745E43C0', 1006, 1006, 3475, -39.2691999999999979, -68.7865000000000038, 'S 39 16 09', 'O 68 47 11', 173, 144);
INSERT INTO bdc.mux_grid VALUES ('173/145', '0106000020E61000000100000001030000000100000005000000685FB2CCC95B51C0DEBE29CAB4CF43C0F43E8CCFE22051C058843E4552E143C0F81A68554F3351C0982F92B7835244C06C3B8E52366E51C01E6A7D3CE64044C0685FB2CCC95B51C0DEBE29CAB4CF43C0', 1007, 1007, 3476, -40.1535999999999973, -69.0729000000000042, 'S 40 09 13', 'O 69 04 22', 173, 145);
INSERT INTO bdc.mux_grid VALUES ('173/146', '0106000020E6100000010000000103000000010000000500000010D9B382466E51C0181B2765E14044C076A8DA736E3351C014B225697A5244C026EAF94B3C4651C05876EC7297C344C0C31AD35A148151C05CDFED6EFEB144C010D9B382466E51C0181B2765E14044C0', 1008, 1008, 3477, -41.0373999999999981, -69.3652000000000015, 'S 41 02 14', 'O 69 21 54', 173, 146);
INSERT INTO bdc.mux_grid VALUES ('173/147', '0106000020E610000001000000010300000001000000050000004094A87A258151C02A74E94FF9B144C0B6474C365D4651C0029EF89A8DC344C022E52819925951C09249DF5C953445C0AC31855D5A9451C0BC1FD011012345C04094A87A258151C02A74E94FF9B144C0', 1009, 1009, 3479, -41.9206000000000003, -69.6637000000000057, 'S 41 55 14', 'O 69 39 49', 173, 147);
INSERT INTO bdc.mux_grid VALUES ('173/148', '0106000020E61000000100000001030000000100000005000000B6B7BC7D6C9451C0245E1FA6FB2245C000493EEFB45951C0EED1DAF18A3445C06CE852FD566D51C0E82D757E7CA545C02257D18B0EA851C01EBAB932ED9345C0B6B7BC7D6C9451C0245E1FA6FB2245C0', 1010, 1010, 3480, -42.8029999999999973, -69.9688000000000017, 'S 42 48 10', 'O 69 58 07', 173, 148);
INSERT INTO bdc.mux_grid VALUES ('173/149', '0106000020E610000001000000010300000001000000050000005E65A5BE21A851C07616E974E79345C00C50F5E17B6D51C057B0F87571A545C066D56BAD918151C0E6BB47D04B1646C0B8EA1B8A37BC51C0042238CFC10446C05E65A5BE21A851C07616E974E79345C0', 1011, 1011, 3481, -43.6848000000000027, -70.2807999999999993, 'S 43 41 05', 'O 70 16 50', 173, 149);
INSERT INTO bdc.mux_grid VALUES ('173/150', '0106000020E61000000100000001030000000100000005000000CCF979E34BBC51C088FA51B9BB0446C024E89BC6B88151C0C6CBF51E401646C068640E5E499651C030D1C238028746C00C76EC7ADCD051C0F0FF1ED37D7546C0CCF979E34BBC51C088FA51B9BB0446C0', 1012, 1012, 3483, -44.565800000000003, -70.600200000000001, 'S 44 33 56', 'O 70 36 00', 173, 150);
INSERT INTO bdc.mux_grid VALUES ('173/151', '0106000020E610000001000000010300000001000000050000002A24A510F2D051C0CA359D5E777546C09C645DD5729651C00E162DD2F58646C03C23CDCF85AB51C0ECDF338A9EF746C0C9E2140B05E651C0A8FFA31620E646C02A24A510F2D051C0CA359D5E777546C0', 1013, 1013, 3484, -45.4461000000000013, -70.9274000000000058, 'S 45 26 45', 'O 70 55 38', 173, 151);
INSERT INTO bdc.mux_grid VALUES ('173/152', '0106000020E61000000100000001030000000100000005000000EA5E12F51BE651C0B8B05F3C19E646C07061C2D2B1AB51C094BEBC6091F746C06421EE5C4FC151C08E539E801F6847C0E01E3E7FB9FB51C0B245415CA75647C0EA5E12F51BE651C0B8B05F3C19E646C0', 1014, 1014, 3485, -46.3254999999999981, -71.2629000000000019, 'S 46 19 31', 'O 71 15 46', 173, 152);
INSERT INTO bdc.mux_grid VALUES ('173/93', '0106000020E61000000100000001030000000100000005000000FDFFFEE3890B4DC02AC86D56503D1B40E703526CF1934CC0539F580840AE1A40EDE24D3A3AAD4CC056A9994BED18174003DFFAB1D2244DC02AD2AE99FDA71740FDFFFEE3890B4DC02AC86D56503D1B40', 1015, 1015, 3517, 6.27210000000000001, -57.6766999999999967, 'N 06 16 19', 'O 57 40 36', 173, 93);
INSERT INTO bdc.mux_grid VALUES ('173/94', '0106000020E61000000100000001030000000100000005000000D2E3BE11D0244DC0D6688975FAA717404C28935835AD4CC03A42A374E7181740D4BDEEBA6FC64CC08289A4D08183134059791A740A3E4DC01EB08AD194121440D2E3BE11D0244DC0D6688975FAA71740', 1016, 1016, 3518, 5.37619999999999987, -57.873899999999999, 'N 05 22 34', 'O 57 52 26', 173, 94);
INSERT INTO bdc.mux_grid VALUES ('173/95', '0106000020E610000001000000010300000001000000050000002028BD34083E4DC00E28462192121440E54689916BC64CC08C4C2FD67C831340F9059CB799DF4CC06CE6AA3B0EDC0F4035E7CF5A36574DC0B84EEC681C7D10402028BD34083E4DC00E28462192121440', 1017, 1017, 3519, 4.48029999999999973, -58.0707999999999984, 'N 04 28 49', 'O 58 04 14', 173, 95);
INSERT INTO bdc.mux_grid VALUES ('173/96', '0106000020E61000000100000001030000000100000005000000925A3C7B34574DC0C46C3D2B1A7D104010E28A4496DF4CC0C390F7FA05DC0F40F5CBA057BAF84CC04D993A0400B108407844528E58704DC013E2BD5F2ECF0940925A3C7B34574DC0C46C3D2B1A7D1040', 1018, 1018, 3520, 3.58429999999999982, -58.2672000000000025, 'N 03 35 03', 'O 58 16 02', 173, 96);
INSERT INTO bdc.mux_grid VALUES ('173/97', '0106000020E61000000100000001030000000100000005000000AB99A20D57704DC0796C65C72ACF094077703C99B7F84CC0D319C973F9B00840D468ACBDD3114DC087641597DE8501400892123273894DC02CB7B1EA0FA40240AB99A20D57704DC0796C65C72ACF0940', 1019, 1019, 3522, 2.68829999999999991, -58.4635000000000034, 'N 02 41 17', 'O 58 27 48', 173, 97);
INSERT INTO bdc.mux_grid VALUES ('173/98', '0106000020E610000001000000010300000001000000050000005CFB8E0F72894DC0D6D1A6330DA4024090FEA4B2D1114DC02D3FC2B3D985014074FBE108E82A4DC0DC12141E5FB5F43F40F8CB6588A24DC03138DD1DC6F1F63F5CFB8E0F72894DC0D6D1A6330DA40240', 1020, 1020, 3523, 1.79220000000000002, -58.6595000000000013, 'N 01 47 31', 'O 58 39 34', 173, 98);
INSERT INTO bdc.mux_grid VALUES ('173/99', '0106000020E6100000010000000103000000010000000500000079FFE9A087A24DC0D606CC6FC2F1F63F7D073EB0E62A4DC091BE00AD58B5F43F933CE455F9434DC0073B4E30C47BD93F923490469ABB4DC00DAEBD9DB536E13F79FFE9A087A24DC0D606CC6FC2F1F63F', 1021, 1021, 3524, 0.896100000000000008, -58.855400000000003, 'N 00 53 45', 'O 58 51 19', 173, 99);
INSERT INTO bdc.mux_grid VALUES ('174/100', '0106000020E61000000100000001030000000100000005000000F99497D223374EC09D0D24BEB136E13F5E09A5A282BF4DC0B2AC07B6B77BD93FC92684B393D84DC03859525307DEDFBF65B276E334504EC0B0EA118D5BECD6BFF99497D223374EC09D0D24BEB136E13F', 1022, 1022, 3525, 0, -60.0163999999999973, 'N 00 00 00', 'O 60 00 59', 174, 100);
INSERT INTO bdc.mux_grid VALUES ('174/101', '0106000020E61000000100000001030000000100000005000000365AEBD834504EC0DD75E2565CECD6BFF37E0FBE93D84DC02ACE818906DEDFBF1D173355A5F14DC07AFDAB51EE4DF6BF60F20E7046694EC0622704C58311F4BF365AEBD834504EC0DD75E2565CECD6BF', 1023, 1023, 3527, -0.896100000000000008, -60.2122000000000028, 'S 00 53 45', 'O 60 12 44', 174, 101);
INSERT INTO bdc.mux_grid VALUES ('174/102', '0106000020E61000000100000001030000000100000005000000993E91C246694EC0A3BC373A8211F4BFA9623311A6F14DC00F261ACEEA4DF6BF5287EA49BA0A4EC00C5B579B245202C0406348FB5A824EC054266651F03301C0993E91C246694EC0A3BC373A8211F4BF', 1024, 1024, 3528, -1.79220000000000002, -60.4080999999999975, 'S 01 47 31', 'O 60 24 29', 174, 102);
INSERT INTO bdc.mux_grid VALUES ('174/103', '0106000020E610000001000000010300000001000000050000000E7CFFAA5B824EC0C2FB01ADEE3301C04432B9B7BB0A4EC0D6A42930215202C050579EAED4234EC022F83AA7437D09C01AA1E4A1749B4EC00F4F1324115F08C00E7CFFAA5B824EC0C2FB01ADEE3301C0', 1025, 1025, 3529, -2.68829999999999991, -60.6041999999999987, 'S 02 41 17', 'O 60 36 15', 174, 103);
INSERT INTO bdc.mux_grid VALUES ('174/104', '0106000020E61000000100000001030000000100000005000000B90924AF759B4EC05F62E99F0E5F08C05C94E9CED6234EC084B407913E7D09C0E5C7EBA2F63C4EC0A5F04658275410C0423D268395B44EC0258F6FBF1E8A0FC0B90924AF759B4EC05F62E99F0E5F08C0', 1026, 1026, 3531, -3.58429999999999982, -60.8004000000000033, 'S 03 35 03', 'O 60 48 01', 174, 104);
INSERT INTO bdc.mux_grid VALUES ('174/105', '0106000020E61000000100000001030000000100000005000000FE296EEE96B44EC027274D5A1B8A0FC0AE41B776F93C4EC038E973F6235410C0AACA254A22564EC055BDD50CA0E913C0FAB2DCC1BFCD4EC0B06788C3895A13C0FE296EEE96B44EC027274D5A1B8A0FC0', 1027, 1027, 3532, -4.48029999999999973, -60.9968999999999966, 'S 04 28 49', 'O 60 59 48', 174, 105);
INSERT INTO bdc.mux_grid VALUES ('174/106', '0106000020E61000000100000001030000000100000005000000A58CDA8BC1CD4EC01286AB9F875A13C08EACCBD225564EC03D37ABD29BE913C0FF2565CC596F4EC0DEE66221097F17C015067485F5E64EC0B43563EEF4EF16C0A58CDA8BC1CD4EC01286AB9F875A13C0', 1028, 1028, 3533, -5.37619999999999987, -61.1936999999999998, 'S 05 22 34', 'O 61 11 37', 174, 106);
INSERT INTO bdc.mux_grid VALUES ('174/107', '0106000020E61000000100000001030000000100000005000000141D03AFF7E64EC0E74C3458F2EF16C0137F970B5E6F4EC042A6D90C047F17C0898B9D579F884EC08F5CB3C45F141BC08C2909FB38004FC034030E104E851AC0141D03AFF7E64EC0E74C3458F2EF16C0', 1029, 1029, 3534, -6.27210000000000001, -61.390900000000002, 'S 06 16 19', 'O 61 23 27', 174, 107);
INSERT INTO bdc.mux_grid VALUES ('174/108', '0106000020E61000000100000001030000000100000005000000BD9833853B004FC0A7C04E064B851AC0A10B684FA4884EC05DEE58D359141BC01FC5B820F5A14EC03328F423A1A91EC03B5284568C194FC07DFAE956921A1EC0BD9833853B004FC0A7C04E064B851AC0', 1030, 1030, 3535, -7.16790000000000038, -61.5885999999999996, 'S 07 10 04', 'O 61 35 18', 174, 108);
INSERT INTO bdc.mux_grid VALUES ('174/109', '0106000020E61000000100000001030000000100000005000000B71384428F194FC09FC722D88E1A1EC066DA82D3FAA14EC0625AE8529AA91EC0A12CB9645DBB4EC0E2B13835651F21C0F465BAD3F1324FC07FE8D577DFD720C0B71384428F194FC09FC722D88E1A1EC0', 1031, 1031, 3538, -8.06359999999999921, -61.7867000000000033, 'S 08 03 49', 'O 61 47 12', 174, 109);
INSERT INTO bdc.mux_grid VALUES ('174/110', '0106000020E610000001000000010300000001000000050000004D9BFA22F5324FC03F25157DDDD720C0548248D563BB4EC092A4315B611F21C024AAE469DAD44EC0498DA360ECE922C01BC396B76B4C4FC0F60D878268A222C04D9BFA22F5324FC03F25157DDDD720C0', 1032, 1032, 3539, -8.95919999999999916, -61.9855000000000018, 'S 08 57 33', 'O 61 59 07', 174, 110);
INSERT INTO bdc.mux_grid VALUES ('174/111', '0106000020E610000001000000010300000001000000050000001A33B56B6F4C4FC088A4714B66A222C0BB0E609BE1D44EC085C93813E8E922C00487F9806EEE4EC0E28D85A764B424C066AB4E51FC654FC0E568BEDFE26C24C01A33B56B6F4C4FC088A4714B66A222C0', 1033, 1033, 3540, -9.85479999999999912, -62.184899999999999, 'S 09 51 17', 'O 62 11 05', 174, 111);
INSERT INTO bdc.mux_grid VALUES ('174/112', '0106000020E61000000100000001030000000100000005000000497A1D6C00664FC0F28A3D6BE06C24C07E3EEC7676EE4EC09A6D98E45FB424C0D6756E061C084FC05573B79BCC7E26C0A1B19FFBA57F4FC0AD905C224D3726C0497A1D6C00664FC0F28A3D6BE06C24C0', 1034, 1034, 3542, -10.7501999999999995, -62.3851000000000013, 'S 10 45 00', 'O 62 23 06', 174, 112);
INSERT INTO bdc.mux_grid VALUES ('174/113', '0106000020E610000001000000010300000001000000050000006C51277FAA7F4FC009F5386F4A3726C03FFDCBC424084FC02AFAEA60C77E26C00F41BF63E5214FC0424D6CCD224928C040951A1E6B994FC02148BADBA50128C06C51277FAA7F4FC009F5386F4A3726C0', 1035, 1035, 3543, -11.6454000000000004, -62.5861000000000018, 'S 11 38 43', 'O 62 35 09', 174, 113);
INSERT INTO bdc.mux_grid VALUES ('174/114', '0106000020E610000001000000010300000001000000050000002AF99B0C70994FC0B9D99AE8A20128C09A8AE7EEEE214FC009A022181D4928C0D9ACC710CD3B4FC05DF4F8CA65132AC0691B7C2E4EB34FC00E2E719BEBCB29C02AF99B0C70994FC0B9D99AE8A20128C0', 1036, 1036, 3544, -12.5404999999999998, -62.7879999999999967, 'S 12 32 25', 'O 62 47 16', 174, 114);
INSERT INTO bdc.mux_grid VALUES ('174/115', '0106000020E610000001000000010300000001000000050000001B2C738A53B34FC04394D966E8CB29C06EDD8B6DD73B4FC0688350985F132AC0A1322E95D5554FC021F3952094DD2BC0518115B251CD4FC0FC031FEF1C962BC01B2C738A53B34FC04394D966E8CB29C0', 1037, 1037, 3545, -13.4354999999999993, -62.9908000000000001, 'S 13 26 07', 'O 62 59 26', 174, 115);
INSERT INTO bdc.mux_grid VALUES ('174/116', '0106000020E61000000100000001030000000100000005000000CFD83B7E57CD4FC0ECFF6D7719962BC0E2E7D5C8E0554FC0A652666D8DDD2BC0AD58E08901704FC08E471B58ACA72DC09849463F78E74FC0D6F4226238602DC0CFD83B7E57CD4FC0ECFF6D7719962BC0', 1038, 1038, 3546, -14.3302999999999994, -63.1946000000000012, 'S 14 19 49', 'O 63 11 40', 174, 116);
INSERT INTO bdc.mux_grid VALUES ('174/117', '0106000020E61000000100000001030000000100000005000000823E967E7EE74FC0498F90A534602DC0EC802F9A0D704FC0FFB0F120A5A72DC0248BA29A538A4FC04663B5F8AC712FC05CA4843FE20050C09041547D3C2A2FC0823E967E7EE74FC0498F90A534602DC0', 1039, 1039, 3548, -15.2249999999999996, -63.3995999999999995, 'S 15 13 29', 'O 63 23 58', 174, 117);
INSERT INTO bdc.mux_grid VALUES ('174/118', '0106000020E61000000100000001030000000100000005000000D2A4609AE50050C00DC9EF79382A2FC08BDDDF8D608A4FC0B2D6D039A5712FC0BC84B587CEA44FC0CE534943CA9D30C06A784B971C0E50C0FECC58E3137A30C0D2A4609AE50050C00DC9EF79382A2FC0', 1040, 1040, 3550, -16.1193999999999988, -63.6058000000000021, 'S 16 07 09', 'O 63 36 20', 174, 118);
INSERT INTO bdc.mux_grid VALUES ('174/119', '0106000020E61000000100000001030000000100000005000000B99C1E2F200E50C07CB52FBD117A30C05FA2B164DCA44FC00AD4EF1DC69D30C00E7B932775BF4FC07B6044C1B08231C010898F906C1B50C0ED418460FC5E31C0B99C1E2F200E50C07CB52FBD117A30C0', 1041, 1041, 3551, -17.0137, -63.8132000000000019, 'S 17 00 49', 'O 63 48 47', 174, 119);
INSERT INTO bdc.mux_grid VALUES ('174/120', '0106000020E6100000010000000103000000010000000500000002E24267701B50C0C5CABF14FA5E31C07BC8B0F583BF4FC04F51CE53AC8231C03375C7684ADA4FC0FF7ED834896732C06038CEA0D32850C074F8C9F5D64332C002E24267701B50C0C5CABF14FA5E31C0', 1042, 1042, 3553, -17.9076999999999984, -64.0220999999999947, 'S 17 54 27', 'O 64 01 19', 174, 120);
INSERT INTO bdc.mux_grid VALUES ('174/121', '0106000020E61000000100000001030000000100000005000000FC0773B8D72850C018932D83D44332C05FBD02305ADA4FC0D45DE27C846732C0B36AE15351F54FC0226C7DDA524C33C0A65E624A533650C065A1C8E0A22833C0FC0773B8D72850C018932D83D44332C0', 1043, 1043, 3554, -18.8016000000000005, -64.2323999999999984, 'S 18 48 05', 'O 64 13 56', 174, 121);
INSERT INTO bdc.mux_grid VALUES ('174/122', '0106000020E61000000100000001030000000100000005000000B49134A5573650C03D3AFE45A02833C05E58DB1C62F54FC069B472D54D4C33C0EAFEC486460850C00CDF59EC0C3134C06EE48B1DED4350C0DE64E55C5F0D34C0B49134A5573650C03D3AFE45A02833C0', 1044, 1044, 3555, -19.6951000000000001, -64.444199999999995, 'S 19 41 42', 'O 64 26 39', 174, 122);
INSERT INTO bdc.mux_grid VALUES ('174/123', '0106000020E61000000100000001030000000100000005000000FAC8F4BDF14350C0D9C37B985C0D34C09AC2C8704F0850C004ED7197073134C05C795C6C001650C08D8E01A2B61535C0BA7F88B9A25150C060650BA30BF234C0FAC8F4BDF14350C0D9C37B985C0D34C0', 1045, 1045, 3556, -20.5884999999999998, -64.6577000000000055, 'S 20 35 18', 'O 64 39 27', 174, 123);
INSERT INTO bdc.mux_grid VALUES ('174/124', '0106000020E610000001000000010300000001000000050000005CBF21A2A75150C00C6674B308F234C02A5EEBE0091650C033353CFAB01535C034E2880CD82350C022CB2C304FFA35C06643BFCD755F50C0FBFB64E9A6D635C05CBF21A2A75150C00C6674B308F234C0', 1046, 1046, 3558, -21.4816000000000003, -64.8730000000000047, 'S 21 28 53', 'O 64 52 22', 174, 124);
INSERT INTO bdc.mux_grid VALUES ('174/125', '0106000020E61000000100000001030000000100000005000000AC2856017B5F50C0A698F3CCA3D635C024580A11E22350C03C964E3249FA35C06408B52ACF3150C0251869C8D5DE36C0EED8001B686D50C08F1A0E6330BB36C0AC2856017B5F50C0A698F3CCA3D635C0', 1047, 1047, 3559, -22.3744000000000014, -65.0901000000000067, 'S 22 22 27', 'O 65 05 24', 174, 125);
INSERT INTO bdc.mux_grid VALUES ('174/126', '0106000020E6100000010000000103000000010000000500000080E5999C6D6D50C01947F4172DBB36C08A7AFAC4D93150C0F82FF770CFDE36C060FD3E9DE73F50C0A511C29849C337C05668DE747B7B50C0C628BF3FA79F37C080E5999C6D6D50C01947F4172DBB36C0', 1048, 1048, 3561, -23.2669999999999995, -65.3092000000000041, 'S 23 16 01', 'O 65 18 32', 174, 126);
INSERT INTO bdc.mux_grid VALUES ('174/127', '0106000020E61000000100000001030000000100000005000000B644B947817B50C0ED770BC4A39F37C00A598BD3F23F50C054BAFDE342C337C0C27DEB4E234E50C039F961CBA9A738C06E6919C3B18950C0D2B66FAB0A8438C0B644B947817B50C0ED770BC4A39F37C0', 1049, 1049, 3563, -24.1593000000000018, -65.5302999999999969, 'S 24 09 33', 'O 65 31 49', 174, 127);
INSERT INTO bdc.mux_grid VALUES ('174/128', '0106000020E61000000100000001030000000100000005000000B637B5EAB78950C034C40AFD068438C0FE74FB272F4E50C00BA243B5A2A738C09E0F7540845C50C065132986F58B39C056D22E030D9850C08C35F0CD596839C0B637B5EAB78950C034C40AFD068438C0', 1050, 1050, 3564, -25.0512000000000015, -65.7536999999999949, 'S 25 03 04', 'O 65 45 13', 174, 128);
INSERT INTO bdc.mux_grid VALUES ('174/129', '0106000020E6100000010000000103000000010000000500000082EC4E83139850C05ECF99EA556839C0B42C88C3905C50C009E95A0AEE8B39C0DA96398A0C6B50C06CEF3AEA2B703AC0A856004A8FA650C0C0D579CA934C3AC082EC4E83139850C05ECF99EA556839C0', 1051, 1051, 3565, -25.9429000000000016, -65.9793999999999983, 'S 25 56 34', 'O 65 58 45', 174, 129);
INSERT INTO bdc.mux_grid VALUES ('174/130', '0106000020E61000000100000001030000000100000005000000F685B12696A650C01EDEC5AF8F4C3AC0E22E1CBF196B50C0D9E8120424703AC0FA62095EBE7950C0B7BE80134C543BC00CBA9EC53AB550C0FBB333BFB7303BC0F685B12696A650C01EDEC5AF8F4C3AC0', 1052, 1052, 3566, -26.8341999999999992, -66.2075999999999993, 'S 26 50 03', 'O 66 12 27', 174, 130);
INSERT INTO bdc.mux_grid VALUES ('174/131', '0106000020E61000000100000001030000000100000005000000BCF23C0342B550C002B3866AB3303BC0DE881F4DCC7950C0A410FABD43543BC0041B1B099C8850C099891F1855383CC0E48438BF11C450C0F82BACC4C4143CC0BCF23C0342B550C002B3866AB3303BC0', 1053, 1053, 3568, -27.7251000000000012, -66.4382999999999981, 'S 27 43 30', 'O 66 26 18', 174, 131);
INSERT INTO bdc.mux_grid VALUES ('174/132', '0106000020E61000000100000001030000000100000005000000D233756219C450C0A58A3733C0143CC09CA46CBBAA8850C00376D34D4C383CC0E63A28F6A79750C0E92AE107461C3DC01CCA309D16D350C08A3F45EDB9F83CC0D233756219C450C0A58A3733C0143CC0', 1054, 1054, 3569, -28.6157000000000004, -66.6718000000000046, 'S 28 36 56', 'O 66 40 18', 174, 132);
INSERT INTO bdc.mux_grid VALUES ('174/133', '0106000020E6100000010000000103000000010000000500000079C719AB1ED350C0E81F031CB5F83CC09AFE6D75B79750C0B715FFC23C1C3DC09650B6AFE4A650C095BA8EEB1D003EC0721962E54BE250C0C6C4924496DC3DC079C719AB1ED350C0E81F031CB5F83CC0', 1055, 1055, 3570, -29.5060000000000002, -66.9081999999999937, 'S 29 30 21', 'O 66 54 29', 174, 133);
INSERT INTO bdc.mux_grid VALUES ('174/134', '0106000020E61000000100000001030000000100000005000000944E696354E250C0D66E413091DC3DC0ECB66806F5A650C0E472D32514003EC04A9091E254B650C07CEC3AC4DBE33EC0F227923FB4F150C06EE8A8CE58C03EC0944E696354E250C0D66E413091DC3DC0', 1056, 1056, 3571, -30.3958000000000013, -67.1477000000000004, 'S 30 23 44', 'O 67 08 51', 174, 134);
INSERT INTO bdc.mux_grid VALUES ('174/135', '0106000020E6100000010000000103000000010000000500000082009633BDF150C0A0BDC57353C03EC013A4F81B66B650C00E11E776D1E33EC098EB7D60FBC550C0BECA7A8A7EC73FC008481B78520151C05077598700A43FC082009633BDF150C0A0BDC57353C03EC0', 1057, 1057, 3574, -31.2852999999999994, -67.3902999999999963, 'S 31 17 06', 'O 67 23 25', 174, 135);
INSERT INTO bdc.mux_grid VALUES ('174/136', '0106000020E61000000100000001030000000100000005000000E00270E85B0151C0FE5F1BE2FAA33FC0E213C3880DC650C0BC2F48AE73C73FC06C6B2423DBD550C03678C596825540C06A5AD182291151C05610AF30C64340C0E00270E85B0151C0FE5F1BE2FAA33FC0', 1058, 1058, 3575, -32.1743000000000023, -67.6363999999999947, 'S 32 10 27', 'O 67 38 10', 174, 136);
INSERT INTO bdc.mux_grid VALUES ('174/137', '0106000020E61000000100000001030000000100000005000000AE574B76331151C024B1D736C34340C05DFB6547EED550C01A7650DD7C5540C0E637434FF7E550C068A12F4937C740C03894287E3C2151C072DCB6A27DB540C0AE574B76331151C024B1D736C34340C0', 1059, 1059, 3576, -33.0628999999999991, -67.8859999999999957, 'S 33 03 46', 'O 67 53 09', 174, 137);
INSERT INTO bdc.mux_grid VALUES ('174/138', '0106000020E61000000100000001030000000100000005000000FCB827FC462151C00993727F7AB540C06613AA7D0BE650C0F8DD224031C740C03E8B273853F650C0EB694DC9DC3841C0D430A5B68E3151C0FC1E9D08262741C0FCB827FC462151C00993727F7AB540C0', 1060, 1060, 3577, -33.9510000000000005, -68.1393999999999949, 'S 33 57 03', 'O 68 08 21', 174, 138);
INSERT INTO bdc.mux_grid VALUES ('174/139', '0106000020E61000000100000001030000000100000005000000308721C7993151C0AED489B9222741C0D819FF7F68F650C00EF7156CD63841C044A27963F20651C0C6B4B67D72AA41C09C0F9CAA234251C066922ACBBE9841C0308721C7993151C0AED489B9222741C0', 1061, 1061, 3578, -34.8387000000000029, -68.3967999999999989, 'S 34 50 19', 'O 68 23 48', 174, 139);
INSERT INTO bdc.mux_grid VALUES ('174/140', '0106000020E6100000010000000103000000010000000500000083C933562F4251C0E07FB44DBB9841C054584AD5080751C07CD362C76BAA41C0E2C2638DD81751C0D2D829C6F71B42C010344D0EFF5251C036857B4C470A42C083C933562F4251C0E07FB44DBB9841C0', 1062, 1062, 3579, -35.7257999999999996, -68.6584000000000003, 'S 35 43 33', 'O 68 39 30', 174, 140);
INSERT INTO bdc.mux_grid VALUES ('174/141', '0106000020E610000001000000010300000001000000050000009036545E0B5351C0768CD89D430A42C0AC94103BF01751C0862A60B1F01B42C0869A1EAD092951C0CA78DBFA6B8D42C06A3C62D0246451C0BADA53E7BE7B42C09036545E0B5351C0768CD89D430A42C0', 1063, 1063, 3581, -36.6124999999999972, -68.9244000000000057, 'S 36 36 45', 'O 68 55 27', 174, 141);
INSERT INTO bdc.mux_grid VALUES ('174/142', '0106000020E61000000100000001030000000100000005000000D86BF3CE316451C0CE5A7E04BB7B42C0E6B105AA222951C02C37D181648D42C0907CEEF9893A51C0CA38B46BCEFE42C08036DC1E997551C06A5C61EE24ED42C0D86BF3CE316451C0CE5A7E04BB7B42C0', 1064, 1064, 3582, -37.4986000000000033, -69.1950999999999965, 'S 37 29 55', 'O 69 11 42', 174, 142);
INSERT INTO bdc.mux_grid VALUES ('174/143', '0106000020E61000000100000001030000000100000005000000D6B9ECD6A67551C09E6E12D420ED42C0529C0D5BA43A51C0F2532288C6FE42C0FE8F9EF05D4C51C0F23B7A5F1E7043C082AD7D6C608751C09E566AAB785E43C0D6B9ECD6A67551C09E6E12D420ED42C0', 1065, 1065, 3583, -38.3841999999999999, -69.470799999999997, 'S 38 23 03', 'O 69 28 14', 174, 143);
INSERT INTO bdc.mux_grid VALUES ('174/144', '0106000020E61000000100000001030000000100000005000000066AF2E96E8751C0DA611356745E43C0649FBBCC794C51C0563A910A167043C09AB388598A5E51C0420AE4125BE143C03C7EBF767F9951C0C831665EB9CF43C0066AF2E96E8751C0DA611356745E43C0', 1066, 1066, 3585, -39.2691999999999979, -69.7516999999999996, 'S 39 16 09', 'O 69 45 05', 174, 144);
INSERT INTO bdc.mux_grid VALUES ('174/145', '0106000020E61000000100000001030000000100000005000000121385C68E9951C06EBE29CAB4CF43C09EF25EC9A75E51C0EA833E4552E143C0BACE3A4F147151C0B02F92B7835244C02CEF604CFBAB51C0356A7D3CE64044C0121385C68E9951C06EBE29CAB4CF43C0', 1067, 1067, 3586, -40.1535999999999973, -70.0381, 'S 40 09 13', 'O 70 02 17', 174, 145);
INSERT INTO bdc.mux_grid VALUES ('174/146', '0106000020E61000000100000001030000000100000005000000D68C867C0BAC51C02C1B2765E14044C03A5CAD6D337151C028B225697A5244C0EE9DCC45018451C07476EC7297C344C088CEA554D9BE51C076DFED6EFEB144C0D68C867C0BAC51C02C1B2765E14044C0', 1068, 1068, 3587, -41.0373999999999981, -70.3303999999999974, 'S 41 02 14', 'O 70 19 49', 174, 146);
INSERT INTO bdc.mux_grid VALUES ('174/147', '0106000020E6100000010000000103000000010000000500000022487B74EABE51C03C74E94FF9B144C098FB1E30228451C0149EF89A8DC344C00499FB12579751C0AC49DF5C953445C090E557571FD251C0D41FD011012345C022487B74EABE51C03C74E94FF9B144C0', 1069, 1069, 3588, -41.9206000000000003, -70.6289000000000016, 'S 41 55 14', 'O 70 37 43', 174, 147);
INSERT INTO bdc.mux_grid VALUES ('174/148', '0106000020E61000000100000001030000000100000005000000666B8F7731D251C04A5E1FA6FB2245C0F6FC10E9799751C002D2DAF18A3445C0649C25F71BAB51C0022E757E7CA545C0D40AA485D3E551C04CBAB932ED9345C0666B8F7731D251C04A5E1FA6FB2245C0', 1070, 1070, 3589, -42.8029999999999973, -70.9338999999999942, 'S 42 48 10', 'O 70 56 02', 174, 148);
INSERT INTO bdc.mux_grid VALUES ('174/149', '0106000020E61000000100000001030000000100000005000000DA1878B8E6E551C0B516E974E79345C01204C8DB40AB51C06EB0F87571A545C06E893EA756BF51C006BC47D04B1646C0369EEE83FCF951C04C2238CFC10446C0DA1878B8E6E551C0B516E974E79345C0', 1071, 1071, 3590, -43.6848000000000027, -71.245900000000006, 'S 43 41 05', 'O 71 14 45', 174, 149);
INSERT INTO bdc.mux_grid VALUES ('174/150', '0106000020E610000001000000010300000001000000050000005EAD4CDD10FA51C0C8FA51B9BB0446C0FE9B6EC07DBF51C0F4CBF51E401646C02A18E1570ED451C0E6D0C238028746C08A29BF74A10E52C0BAFF1ED37D7546C05EAD4CDD10FA51C0C8FA51B9BB0446C0', 1072, 1072, 3591, -44.565800000000003, -71.5652999999999935, 'S 44 33 56', 'O 71 33 55', 174, 150);
INSERT INTO bdc.mux_grid VALUES ('174/151', '0106000020E61000000100000001030000000100000005000000ECD7770AB70E52C07E359D5E777546C05E1830CF37D451C0C2152DD2F58646C0FED69FC94AE951C0A8DF338A9EF746C08C96E704CA2352C064FFA31620E646C0ECD7770AB70E52C07E359D5E777546C0', 1073, 1073, 3592, -45.4461000000000013, -71.8924999999999983, 'S 45 26 45', 'O 71 53 33', 174, 151);
INSERT INTO bdc.mux_grid VALUES ('174/93', '0106000020E610000001000000010300000001000000050000008B67A4D713874DC021C86D56503D1B40976BF75F7B0F4DC0759F580840AE1A409C4AF32DC4284DC0BBA9994BED1817408E46A0A55CA04DC068D2AE99FDA717408B67A4D713874DC021C86D56503D1B40', 1074, 1074, 3624, 6.27210000000000001, -58.6418999999999997, 'N 06 16 19', 'O 58 38 30', 174, 93);
INSERT INTO bdc.mux_grid VALUES ('174/94', '0106000020E61000000100000001030000000100000005000000794B64055AA04DC033698975FAA71740D18F384CBF284DC06E42A374E71817405B2594AEF9414DC07D89A4D08183134003E1BF6794B94DC042B08AD194121440794B64055AA04DC033698975FAA71740', 1075, 1075, 3625, 5.37619999999999987, -58.839100000000002, 'N 05 22 34', 'O 58 50 20', 174, 94);
INSERT INTO bdc.mux_grid VALUES ('174/95', '0106000020E61000000100000001030000000100000005000000C68F622892B94DC02A2846219212144089AE2E85F5414DC0A94C2FD67C8313409B6D41AB235B4DC0B0E6AA3B0EDC0F40D84E754EC0D24DC0DA4EEC681C7D1040C68F622892B94DC02A28462192121440', 1076, 1076, 3626, 4.48029999999999973, -59.035899999999998, 'N 04 28 49', 'O 59 02 09', 174, 95);
INSERT INTO bdc.mux_grid VALUES ('174/96', '0106000020E610000001000000010300000001000000050000002EC2E16EBED24DC0DE6C3D2B1A7D1040BE493038205B4DC02291F7FA05DC0F40A133464B44744DC0299A3A0400B1084015ACF781E2EB4DC0C7E2BD5F2ECF09402EC2E16EBED24DC0DE6C3D2B1A7D1040', 1077, 1077, 3628, 3.58429999999999982, -59.2323999999999984, 'N 03 35 03', 'O 59 13 56', 174, 96);
INSERT INTO bdc.mux_grid VALUES ('174/97', '0106000020E610000001000000010300000001000000050000004B014801E1EB4DC0336D65C72ACF094017D8E18C41744DC08C1AC973F9B0084074D051B15D8D4DC0C8641597DE850140A8F9B725FD044EC06FB7B1EA0FA402404B014801E1EB4DC0336D65C72ACF0940', 1078, 1078, 3629, 2.68829999999999991, -59.428600000000003, 'N 02 41 17', 'O 59 25 43', 174, 97);
INSERT INTO bdc.mux_grid VALUES ('174/98', '0106000020E61000000100000001030000000100000005000000FA623403FC044EC013D2A6330DA402403A664AA65B8D4DC08A3FC2B3D9850140206387FC71A64DC0B012141E5FB5F43FE05F7159121E4EC0C437DD1DC6F1F63FFA623403FC044EC013D2A6330DA40240', 1079, 1079, 3630, 1.79220000000000002, -59.6246000000000009, 'N 01 47 31', 'O 59 37 28', 174, 98);
INSERT INTO bdc.mux_grid VALUES ('174/99', '0106000020E610000001000000010300000001000000050000001B678F94111E4EC06D06CC6FC2F1F63F216FE3A370A64DC03EBE00AD58B5F43F39A4894983BF4DC07F3A4E30C47BD93F349C353A24374EC0A8ADBD9DB536E13F1B678F94111E4EC06D06CC6FC2F1F63F', 1080, 1080, 3631, 0.896100000000000008, -59.8205999999999989, 'N 00 53 45', 'O 59 49 13', 174, 99);
INSERT INTO bdc.mux_grid VALUES ('175/100', '0106000020E610000001000000010300000001000000050000009EFC3CC6ADB24EC0C10D24BEB136E13F00714A960C3B4EC0A0AC07B6B77BD93F6B8E29A71D544EC0B759525307DEDFBF091A1CD7BECB4EC0D3EA118D5BECD6BF9EFC3CC6ADB24EC0C10D24BEB136E13F', 1081, 1081, 3633, 0, -60.9814999999999969, 'N 00 00 00', 'O 60 58 53', 175, 100);
INSERT INTO bdc.mux_grid VALUES ('175/101', '0106000020E61000000100000001030000000100000005000000D9C190CCBECB4EC00176E2565CECD6BF95E6B4B11D544EC0A8CE818906DEDFBFBF7ED8482F6D4EC0F7FDAB51EE4DF6BF055AB463D0E44EC0CD2704C58311F4BFD9C190CCBECB4EC00176E2565CECD6BF', 1082, 1082, 3635, -0.896100000000000008, -61.1773999999999987, 'S 00 53 45', 'O 61 10 38', 175, 101);
INSERT INTO bdc.mux_grid VALUES ('175/102', '0106000020E610000001000000010300000001000000050000003DA636B6D0E44EC020BD373A8211F4BF4ECAD804306D4EC08C261ACEEA4DF6BFF5EE8F3D44864EC0445B579B245202C0E4CAEDEEE4FD4EC08C266651F03301C03DA636B6D0E44EC020BD373A8211F4BF', 1083, 1083, 3636, -1.79220000000000002, -61.3733000000000004, 'S 01 47 31', 'O 61 22 23', 175, 102);
INSERT INTO bdc.mux_grid VALUES ('175/103', '0106000020E61000000100000001030000000100000005000000A8E3A49EE5FD4EC011FC01ADEE3301C0F1995EAB45864EC0FCA42930215202C0FBBE43A25E9F4EC0C7F73AA7437D09C0B4088A95FE164FC0DB4E1324115F08C0A8E3A49EE5FD4EC011FC01ADEE3301C0', 1084, 1084, 3638, -2.68829999999999991, -61.5692999999999984, 'S 02 41 17', 'O 61 34 09', 175, 103);
INSERT INTO bdc.mux_grid VALUES ('175/104', '0106000020E610000001000000010300000001000000050000005971C9A2FF164FC01C62E99F0E5F08C0FCFB8EC2609F4EC041B407913E7D09C0852F919680B84EC083F04658275410C0E4A4CB761F304FC0E38E6FBF1E8A0FC05971C9A2FF164FC01C62E99F0E5F08C0', 1085, 1085, 3639, -3.58429999999999982, -61.7655999999999992, 'S 03 35 03', 'O 61 45 55', 175, 104);
INSERT INTO bdc.mux_grid VALUES ('175/105', '0106000020E61000000100000001030000000100000005000000A49113E220304FC0DB264D5A1B8A0FC048A95C6A83B84EC01DE973F6235410C04532CB3DACD14EC03ABDD50CA0E913C0A01A82B549494FC08B6788C3895A13C0A49113E220304FC0DB264D5A1B8A0FC0', 1086, 1086, 3640, -4.48029999999999973, -61.9620000000000033, 'S 04 28 49', 'O 61 57 43', 175, 105);
INSERT INTO bdc.mux_grid VALUES ('175/106', '0106000020E6100000010000000103000000010000000500000037F47F7F4B494FC00086AB9F875A13C0451471C6AFD14EC00137ABD29BE913C0BA8D0AC0E3EA4EC022E76221097F17C0AC6D19797F624FC0213663EEF4EF16C037F47F7F4B494FC00086AB9F875A13C0', 1087, 1087, 3641, -5.37619999999999987, -62.1587999999999994, 'S 05 22 34', 'O 62 09 31', 175, 106);
INSERT INTO bdc.mux_grid VALUES ('175/107', '0106000020E61000000100000001030000000100000005000000AF84A8A281624FC0514D3458F2EF16C0BEE63CFFE7EA4EC099A6D90C047F17C033F3424B29044FC0E65CB3C45F141BC02591AEEEC27B4FC09E030E104E851AC0AF84A8A281624FC0514D3458F2EF16C0', 1088, 1088, 3642, -6.27210000000000001, -62.3560000000000016, 'S 06 16 19', 'O 62 21 21', 175, 107);
INSERT INTO bdc.mux_grid VALUES ('175/108', '0106000020E610000001000000010300000001000000050000005F00D978C57B4FC00CC14E064B851AC045730D432E044FC0C0EE58D359141BC0BD2C5E147F1D4FC01428F423A1A91EC0DBB9294A16954FC05FFAE956921A1EC05F00D978C57B4FC00CC14E064B851AC0', 1089, 1089, 3644, -7.16790000000000038, -62.5536999999999992, 'S 07 10 04', 'O 62 33 13', 175, 108);
INSERT INTO bdc.mux_grid VALUES ('175/109', '0106000020E610000001000000010300000001000000050000005B7B293619954FC07DC722D88E1A1EC0F64128C7841D4FC0555AE8529AA91EC03C945E58E7364FC099B23835651F21C0A1CD5FC77BAE4FC02DE9D577DFD720C05B7B293619954FC07DC722D88E1A1EC0', 1090, 1090, 3646, -8.06359999999999921, -62.7518999999999991, 'S 08 03 49', 'O 62 45 06', 175, 109);
INSERT INTO bdc.mux_grid VALUES ('175/110', '0106000020E61000000100000001030000000100000005000000D602A0167FAE4FC00126157DDDD720C001EAEDC8ED364FC040A5315B611F21C0C1118A5D64504FC0F68CA360ECE922C0962A3CABF5C74FC0B60D878268A222C0D602A0167FAE4FC00126157DDDD720C0', 1091, 1091, 3647, -8.95919999999999916, -62.9506999999999977, 'S 08 57 33', 'O 62 57 02', 175, 110);
INSERT INTO bdc.mux_grid VALUES ('175/111', '0106000020E61000000100000001030000000100000005000000C59A5A5FF9C74FC02CA4714B66A222C04476058F6B504FC03FC93813E8E922C096EE9E74F8694FC01E8E85A764B424C01813F44486E14FC00B69BEDFE26C24C0C59A5A5FF9C74FC02CA4714B66A222C0', 1092, 1092, 3649, -9.85479999999999912, -63.1501000000000019, 'S 09 51 17', 'O 63 09 00', 175, 111);
INSERT INTO bdc.mux_grid VALUES ('175/112', '0106000020E61000000100000001030000000100000005000000F0E1C25F8AE14FC0208B3D6BE06C24C048A6916A006A4FC0B36D98E45FB424C0A0DD13FAA5834FC06E73B79BCC7E26C0481945EF2FFB4FC0DA905C224D3726C0F0E1C25F8AE14FC0208B3D6BE06C24C0', 1093, 1093, 3650, -10.7501999999999995, -63.3502999999999972, 'S 10 45 00', 'O 63 21 00', 175, 112);
INSERT INTO bdc.mux_grid VALUES ('175/113', '0106000020E6100000010000000103000000010000000500000034B9CC7234FB4FC023F5386F4A3726C0E36471B8AE834FC059FAEA60C77E26C0B4A864576F9D4FC0714D6CCD224928C082FEDF887A0A50C03B48BADBA50128C034B9CC7234FB4FC023F5386F4A3726C0', 1094, 1094, 3651, -11.6454000000000004, -63.5512000000000015, 'S 11 38 43', 'O 63 33 04', 175, 113);
INSERT INTO bdc.mux_grid VALUES ('175/114', '0106000020E610000001000000010300000001000000050000007CB020007D0A50C0CED99AE8A20128C02CF28CE2789D4FC043A022181D4928C06B146D0457B74FC081F4F8CA65132AC09CC110116C1750C00B2E719BEBCB29C07CB020007D0A50C0CED99AE8A20128C0', 1095, 1095, 3652, -12.5404999999999998, -63.7531000000000034, 'S 12 32 25', 'O 63 45 11', 175, 114);
INSERT INTO bdc.mux_grid VALUES ('175/115', '0106000020E61000000100000001030000000100000005000000DA490CBF6E1750C05E94D966E8CB29C03745316161B74FC0668350985F132AC0659AD3885FD14FC0B7F2952094DD2BC07474DDD26D2450C0AD031FEF1C962BC0DA490CBF6E1750C05E94D966E8CB29C0', 1096, 1096, 3653, -13.4354999999999993, -63.9558999999999997, 'S 13 26 07', 'O 63 57 21', 175, 115);
INSERT INTO bdc.mux_grid VALUES ('175/116', '0106000020E6100000010000000103000000010000000500000044A0F0B8702450C087FF6D7719962BC05B4F7BBC6AD14FC06A52666D8DDD2BC02DC0857D8BEB4FC0D4471B58ACA72DC0AED87519813150C0F1F4226238602DC044A0F0B8702450C087FF6D7719962BC0', 1097, 1097, 3655, -14.3302999999999994, -64.1598000000000042, 'S 14 19 49', 'O 64 09 35', 175, 116);
INSERT INTO bdc.mux_grid VALUES ('175/117', '0106000020E6100000010000000103000000010000000500000020D31D39843150C0688F90A534602DC063E8D48D97EB4FC049B1F120A5A72DC04AF923C7EE0250C00F63B5F8AC712FC038585739A73E50C03041547D3C2A2FC020D31D39843150C0688F90A534602DC0', 1098, 1098, 3656, -15.2249999999999996, -64.3648000000000025, 'S 15 13 29', 'O 64 21 53', 175, 117);
INSERT INTO bdc.mux_grid VALUES ('175/118', '0106000020E610000001000000010300000001000000050000009E583394AA3E50C0BAC8EF79382A2FC0A2A2C240F50250C04CD6D039A5712FC03E76AD3D2C1050C0DE534943CA9D30C03A2C1E91E14B50C017CD58E3137A30C09E583394AA3E50C0BAC8EF79382A2FC0', 1099, 1099, 3658, -16.1193999999999988, -64.5708999999999946, 'S 16 07 09', 'O 64 34 15', 175, 118);
INSERT INTO bdc.mux_grid VALUES ('175/119', '0106000020E61000000100000001030000000100000005000000A450F128E54B50C086B52FBD117A30C0F6842B2C331050C028D4EF1DC69D30C052719C8D7F1D50C0D36044C1B08231C0003D628A315950C030428460FC5E31C0A450F128E54B50C086B52FBD117A30C0', 1100, 1100, 3660, -17.0137, -64.7784000000000049, 'S 17 00 49', 'O 64 46 42', 175, 119);
INSERT INTO bdc.mux_grid VALUES ('175/120', '0106000020E61000000100000001030000000100000005000000EA951561355950C00CCBBF14FA5E31C02A18ABF4861D50C09351CE53AC8231C0866E362EEA2A50C01B7FD834896732C046ECA09A986650C093F8C9F5D64332C0EA951561355950C00CCBBF14FA5E31C0', 1101, 1101, 3661, -17.9076999999999984, -64.9872000000000014, 'S 17 54 27', 'O 64 59 13', 175, 120);
INSERT INTO bdc.mux_grid VALUES ('175/121', '0106000020E61000000100000001030000000100000005000000D2BB45B29C6650C041932D83D44332C07A12D411F22A50C0045EE27C846732C02269C3A36D3850C0226C7DDA524C33C07C123544187450C05CA1C8E0A22833C0D2BB45B29C6650C041932D83D44332C0', 1102, 1102, 3662, -18.8016000000000005, -65.1975000000000051, 'S 18 48 05', 'O 65 11 51', 175, 121);
INSERT INTO bdc.mux_grid VALUES ('175/122', '0106000020E61000000100000001030000000100000005000000A845079F1C7450C0233AFE45A02833C0EC5F4008763850C072B472D54D4C33C0A1B297800B4650C0AFDE59EC0C3134C05C985E17B28150C06264E55C5F0D34C0A845079F1C7450C0233AFE45A02833C0', 1103, 1103, 3663, -19.6951000000000001, -65.4093000000000018, 'S 19 41 42', 'O 65 24 33', 175, 122);
INSERT INTO bdc.mux_grid VALUES ('175/123', '0106000020E61000000100000001030000000100000005000000B07CC7B7B68150C07BC37B985C0D34C07C769B6A144650C08DEC7197073134C0462D2F66C55350C0978E01A2B61535C076335BB3678F50C086650BA30BF234C0B07CC7B7B68150C07BC37B985C0D34C0', 1104, 1104, 3665, -20.5884999999999998, -65.6229000000000013, 'S 20 35 18', 'O 65 37 22', 175, 123);
INSERT INTO bdc.mux_grid VALUES ('175/124', '0106000020E610000001000000010300000001000000050000003C73F49B6C8F50C01C6674B308F234C0F411BEDACE5350C051353CFAB01535C004965B069D6150C0BFCB2C304FFA35C04CF791C73A9D50C08BFC64E9A6D635C03C73F49B6C8F50C01C6674B308F234C0', 1105, 1105, 3666, -21.4816000000000003, -65.8380999999999972, 'S 21 28 53', 'O 65 50 17', 175, 124);
INSERT INTO bdc.mux_grid VALUES ('175/125', '0106000020E6100000010000000103000000010000000500000092DC28FB3F9D50C03699F3CCA3D635C00A0CDD0AA76150C0CD964E3249FA35C042BC8724946F50C0361869C8D5DE36C0CC8CD3142DAB50C0A01A0E6330BB36C092DC28FB3F9D50C03699F3CCA3D635C0', 1106, 1106, 3667, -22.3744000000000014, -66.0551999999999992, 'S 22 22 27', 'O 66 03 18', 175, 125);
INSERT INTO bdc.mux_grid VALUES ('175/126', '0106000020E6100000010000000103000000010000000500000068996C9632AB50C02347F4172DBB36C0722ECDBE9E6F50C00230F770CFDE36C042B11197AC7D50C02E11C29849C337C0381CB16E40B950C04F28BF3FA79F37C068996C9632AB50C02347F4172DBB36C0', 1107, 1107, 3670, -23.2669999999999995, -66.2742999999999967, 'S 23 16 01', 'O 66 16 27', 175, 126);
INSERT INTO bdc.mux_grid VALUES ('175/127', '0106000020E610000001000000010300000001000000050000009AF88B4146B950C076770BC4A39F37C0A80C5ECDB77D50C007BAFDE342C337C07231BE48E88B50C0EBF961CBA9A738C0641DECBC76C750C05AB76FAB0A8438C09AF88B4146B950C076770BC4A39F37C0', 1108, 1108, 3671, -24.1593000000000018, -66.4955000000000069, 'S 24 09 33', 'O 66 29 43', 175, 127);
INSERT INTO bdc.mux_grid VALUES ('175/128', '0106000020E61000000100000001030000000100000005000000A2EB87E47CC750C0C2C40AFD068438C0E828CE21F48B50C09BA243B5A2A738C080C3473A499A50C074132986F58B39C03A8601FDD1D550C09C35F0CD596839C0A2EB87E47CC750C0C2C40AFD068438C0', 1109, 1109, 3672, -25.0512000000000015, -66.718900000000005, 'S 25 03 04', 'O 66 43 07', 175, 128);
INSERT INTO bdc.mux_grid VALUES ('175/129', '0106000020E6100000010000000103000000010000000500000044A0217DD8D550C081CF99EA556839C076E05ABD559A50C02DE95A0AEE8B39C09C4A0C84D1A850C08FEF3AEA2B703AC06A0AD34354E450C0E3D579CA934C3AC044A0217DD8D550C081CF99EA556839C0', 1110, 1110, 3673, -25.9429000000000016, -66.9445999999999941, 'S 25 56 34', 'O 66 56 40', 175, 129);
INSERT INTO bdc.mux_grid VALUES ('175/130', '0106000020E61000000100000001030000000100000005000000E43984205BE450C027DEC5AF8F4C3AC0AEE2EEB8DEA850C0F6E8120424703AC0C416DC5783B750C0D3BE80134C543BC0FA6D71BFFFF250C004B433BFB7303BC0E43984205BE450C027DEC5AF8F4C3AC0', 1111, 1111, 3675, -26.8341999999999992, -67.1727000000000061, 'S 26 50 03', 'O 67 10 21', 175, 130);
INSERT INTO bdc.mux_grid VALUES ('175/131', '0106000020E610000001000000010300000001000000050000009EA60FFD06F350C012B3866AB3303BC09C3CF24691B750C0C810FABD43543BC0BCCEED0261C650C03D891F1855383CC0BE380BB9D60151C0872BACC4C4143CC09EA60FFD06F350C012B3866AB3303BC0', 1112, 1112, 3676, -27.7251000000000012, -67.403499999999994, 'S 27 43 30', 'O 67 24 12', 175, 131);
INSERT INTO bdc.mux_grid VALUES ('175/132', '0106000020E61000000100000001030000000100000005000000AEE7475CDE0151C0348A3733C0143CC056583FB56FC650C0A575D34D4C383CC0AAEEFAEF6CD550C00B2BE107461C3DC0027E0397DB1051C0983F45EDB9F83CC0AEE7475CDE0151C0348A3733C0143CC0', 1113, 1113, 3677, -28.6157000000000004, -67.6370000000000005, 'S 28 36 56', 'O 67 38 13', 175, 132);
INSERT INTO bdc.mux_grid VALUES ('175/133', '0106000020E610000001000000010300000001000000050000003E7BECA4E31051C00620031CB5F83CC062B2406F7CD550C0D815FFC23C1C3DC0540489A9A9E450C035BA8EEB1D003EC030CD34DF102051C065C4924496DC3DC03E7BECA4E31051C00620031CB5F83CC0', 1114, 1114, 3678, -29.5060000000000002, -67.8734000000000037, 'S 29 30 21', 'O 67 52 24', 175, 133);
INSERT INTO bdc.mux_grid VALUES ('175/134', '0106000020E6100000010000000103000000010000000500000034023C5D192051C0886E413091DC3DC0AE6A3B00BAE450C08172D32514003EC00C4464DC19F450C01BEC3AC4DBE33EC092DB6439792F51C01FE8A8CE58C03EC034023C5D192051C0886E413091DC3DC0', 1115, 1115, 3680, -30.3958000000000013, -68.1127999999999929, 'S 30 23 44', 'O 68 06 46', 175, 134);
INSERT INTO bdc.mux_grid VALUES ('175/135', '0106000020E6100000010000000103000000010000000500000060B4682D822F51C02DBDC57353C03EC03658CB152BF450C07010E776D1E33EC0CE9F505AC00351C01FCB7A8A7EC73FC0F8FBED71173F51C0DB77598700A43FC060B4682D822F51C02DBDC57353C03EC0', 1116, 1116, 3682, -31.2852999999999994, -68.3555000000000064, 'S 31 17 06', 'O 68 21 19', 175, 135);
INSERT INTO bdc.mux_grid VALUES ('175/136', '0106000020E61000000100000001030000000100000005000000F6B642E2203F51C072601BE2FAA33FC0B2C79582D20351C05B3048AE73C73FC03D1FF71CA01351C08478C596825540C0820EA47CEE4E51C09010AF30C64340C0F6B642E2203F51C072601BE2FAA33FC0', 1117, 1117, 3683, -32.1743000000000023, -68.6015000000000015, 'S 32 10 27', 'O 68 36 05', 175, 136);
INSERT INTO bdc.mux_grid VALUES ('175/137', '0106000020E61000000100000001030000000100000005000000AE0B1E70F84E51C064B1D736C34340C018AF3841B31351C06E7650DD7C5540C090EB1549BC2351C03CA12F4937C740C02848FB77015F51C032DCB6A27DB540C0AE0B1E70F84E51C064B1D736C34340C0', 1118, 1118, 3685, -33.0628999999999991, -68.8511000000000024, 'S 33 03 46', 'O 68 51 04', 175, 137);
INSERT INTO bdc.mux_grid VALUES ('175/138', '0106000020E61000000100000001030000000100000005000000A46CFAF50B5F51C0DE92727F7AB540C052C77C77D02351C0B8DD224031C740C03C3FFA31183451C02A6A4DC9DC3841C08CE477B0536F51C0501F9D08262741C0A46CFAF50B5F51C0DE92727F7AB540C0', 1119, 1119, 3686, -33.9510000000000005, -69.1045000000000016, 'S 33 57 03', 'O 69 06 16', 175, 138);
INSERT INTO bdc.mux_grid VALUES ('175/139', '0106000020E61000000100000001030000000100000005000000263BF4C05E6F51C0F0D489B9222741C08ACDD1792D3451C066F7156CD63841C0E5554C5DB74451C09EB4B67D72AA41C080C36EA4E87F51C028922ACBBE9841C0263BF4C05E6F51C0F0D489B9222741C0', 1120, 1120, 3687, -34.8387000000000029, -69.3619000000000057, 'S 34 50 19', 'O 69 21 42', 175, 139);
INSERT INTO bdc.mux_grid VALUES ('175/140', '0106000020E610000001000000010300000001000000050000007C7D0650F47F51C09E7FB44DBB9841C0080C1DCFCD4451C04ED362C76BAA41C0967636879D5551C0A4D829C6F71B42C00AE81F08C49051C0F2847B4C470A42C07C7D0650F47F51C09E7FB44DBB9841C0', 1121, 1121, 3688, -35.7257999999999996, -69.623500000000007, 'S 35 43 33', 'O 69 37 24', 175, 140);
INSERT INTO bdc.mux_grid VALUES ('175/141', '0106000020E6100000010000000103000000010000000500000034EA2658D09051C04E8CD89D430A42C09448E334B55551C04A2A60B1F01B42C06C4EF1A6CE6651C08E78DBFA6B8D42C00CF034CAE9A151C092DA53E7BE7B42C034EA2658D09051C04E8CD89D430A42C0', 1122, 1122, 3689, -36.6124999999999972, -69.8894999999999982, 'S 36 36 45', 'O 69 53 22', 175, 141);
INSERT INTO bdc.mux_grid VALUES ('175/142', '0106000020E610000001000000010300000001000000050000005C1FC6C8F6A151C0AE5A7E04BB7B42C0B065D8A3E76651C0F836D181648D42C06C30C1F34E7851C01439B46BCEFE42C018EAAE185EB351C0CA5C61EE24ED42C05C1FC6C8F6A151C0AE5A7E04BB7B42C0', 1123, 1123, 3690, -37.4986000000000033, -70.1602000000000032, 'S 37 29 55', 'O 70 09 36', 175, 142);
INSERT INTO bdc.mux_grid VALUES ('175/143', '0106000020E61000000100000001030000000100000005000000BE6DBFD06BB351C0E46E12D420ED42C03A50E054697851C038542288C6FE42C0E64371EA228A51C03A3C7A5F1E7043C06C61506625C551C0E6566AAB785E43C0BE6DBFD06BB351C0E46E12D420ED42C0', 1124, 1124, 3691, -38.3841999999999999, -70.4359000000000037, 'S 38 23 03', 'O 70 26 09', 175, 143);
INSERT INTO bdc.mux_grid VALUES ('175/144', '0106000020E61000000100000001030000000100000005000000CE1DC5E333C551C02A621356745E43C02E538EC63E8A51C0A63A910A167043C078675B534F9C51C0120BE4125BE143C01A32927044D751C09632665EB9CF43C0CE1DC5E333C551C02A621356745E43C0', 1125, 1125, 3694, -39.2691999999999979, -70.7168000000000063, 'S 39 16 09', 'O 70 43 00', 175, 144);
INSERT INTO bdc.mux_grid VALUES ('175/145', '0106000020E61000000100000001030000000100000005000000F0C657C053D751C03CBF29CAB4CF43C07CA631C36C9C51C0B8843E4552E143C06E820D49D9AE51C0822F92B7835244C0E0A23346C0E951C0066A7D3CE64044C0F0C657C053D751C03CBF29CAB4CF43C0', 1126, 1126, 3695, -40.1535999999999973, -71.0032000000000068, 'S 40 09 13', 'O 71 00 11', 175, 145);
INSERT INTO bdc.mux_grid VALUES ('175/146', '0106000020E61000000100000001030000000100000005000000D4405976D0E951C0E61A2765E14044C0F40F8067F8AE51C0F9B125697A5244C0A8519F3FC6C151C04476EC7297C344C08882784E9EFC51C032DFED6EFEB144C0D4405976D0E951C0E61A2765E14044C0', 1127, 1127, 3697, -41.0373999999999981, -71.2955000000000041, 'S 41 02 14', 'O 71 17 43', 175, 146);
INSERT INTO bdc.mux_grid VALUES ('175/147', '0106000020E61000000100000001030000000100000005000000B2FB4D6EAFFC51C01874E94FF9B144C06EAFF129E7C151C0DC9DF89A8DC344C0DA4CCE0C1CD551C07449DF5C953445C022992A51E40F52C0B01FD011012345C0B2FB4D6EAFFC51C01874E94FF9B144C0', 1128, 1128, 3698, -41.9206000000000003, -71.5939999999999941, 'S 41 55 14', 'O 71 35 38', 175, 147);
INSERT INTO bdc.mux_grid VALUES ('175/148', '0106000020E610000001000000010300000001000000050000004E1F6271F60F52C00C5E1FA6FB2245C098B0E3E23ED551C0D9D1DAF18A3445C00650F8F0E0E851C0DA2D757E7CA545C0BEBE767F982352C00EBAB932ED9345C04E1F6271F60F52C00C5E1FA6FB2245C0', 1129, 1129, 3699, -42.8029999999999973, -71.8991000000000042, 'S 42 48 10', 'O 71 53 56', 175, 148);
INSERT INTO bdc.mux_grid VALUES ('175/91', '0106000020E6100000010000000103000000010000000500000081708072DECF4DC03029B4B7DC332140C0B8BE884B584DC090FD21E357EC204099F0C5D9B7714DC005314C588B431E405CA887C34AE94DC04488700195D21E4081708072DECF4DC03029B4B7DC332140', 1130, 1130, 3734, 8.06359999999999921, -59.2111999999999981, 'N 08 03 49', 'O 59 12 40', 175, 91);
INSERT INTO bdc.mux_grid VALUES ('175/92', '0106000020E6100000010000000103000000010000000500000039CD8D5D47E94DC0AFC4BFF090D21E40818BED7FB1714DC03D166ABF83431E40DA3909F00A8B4DC05233A3BE46AE1A40947BA9CDA0024EC0C6E1F8EF533D1B4039CD8D5D47E94DC0AFC4BFF090D21E40', 1131, 1131, 3735, 7.16790000000000038, -59.409399999999998, 'N 07 10 04', 'O 59 24 33', 175, 92);
INSERT INTO bdc.mux_grid VALUES ('175/93', '0106000020E610000001000000010300000001000000050000003CCF49CB9D024EC055C86D56503D1B4026D39C53058B4DC07F9F580840AE1A4028B298214EA44DC0C6A9994BED1817403EAE4599E61B4EC09BD2AE99FDA717403CCF49CB9D024EC055C86D56503D1B40', 1132, 1132, 3737, 6.27210000000000001, -59.6069999999999993, 'N 06 16 19', 'O 59 36 25', 175, 93);
INSERT INTO bdc.mux_grid VALUES ('175/94', '0106000020E6100000010000000103000000010000000500000026B309F9E31B4EC061698975FAA717407CF7DD3F49A44DC09C42A374E7181740068D39A283BD4DC0A989A4D081831340AD48655B1E354EC06FB08AD19412144026B309F9E31B4EC061698975FAA71740', 1133, 1133, 3738, 5.37619999999999987, -59.8042000000000016, 'N 05 22 34', 'O 59 48 15', 175, 94);
INSERT INTO bdc.mux_grid VALUES ('175/95', '0106000020E610000001000000010300000001000000050000006AF7071C1C354EC04F284621921214402C16D4787FBD4DC0CE4C2FD67C83134042D5E69EADD64DC07BE6AA3B0EDC0F4080B61A424A4E4EC0BF4EEC681C7D10406AF7071C1C354EC04F28462192121440', 1134, 1134, 3740, 4.48029999999999973, -60.0009999999999977, 'N 04 28 49', 'O 60 00 03', 175, 95);
INSERT INTO bdc.mux_grid VALUES ('175/96', '0106000020E61000000100000001030000000100000005000000CF298762484E4EC0BA6C3D2B1A7D10405DB1D52BAAD64DC0D990F7FA05DC0F40429BEB3ECEEF4DC0E6993A0400B10840B3139D756C674EC084E2BD5F2ECF0940CF298762484E4EC0BA6C3D2B1A7D1040', 1135, 1135, 3741, 3.58429999999999982, -60.197499999999998, 'N 03 35 03', 'O 60 11 51', 175, 96);
INSERT INTO bdc.mux_grid VALUES ('175/97', '0106000020E61000000100000001030000000100000005000000F468EDF46A674EC0086D65C72ACF0940B73F8780CBEF4DC04E1AC973F9B008401238F7A4E7084EC009651597DE8501404F615D1987804EC0C4B7B1EA0FA40240F468EDF46A674EC0086D65C72ACF0940', 1136, 1136, 3742, 2.68829999999999991, -60.3937999999999988, 'N 02 41 17', 'O 60 23 37', 175, 97);
INSERT INTO bdc.mux_grid VALUES ('175/98', '0106000020E610000001000000010300000001000000050000009ACAD9F685804EC058D2A6330DA40240D7CDEF99E5084EC0C33FC2B3D9850140BFCA2CF0FB214EC0A712141E5FB5F43F82C7164D9C994EC0D137DD1DC6F1F63F9ACAD9F685804EC058D2A6330DA40240', 1137, 1137, 3743, 1.79220000000000002, -60.5897999999999968, 'N 01 47 31', 'O 60 35 23', 175, 98);
INSERT INTO bdc.mux_grid VALUES ('175/99', '0106000020E61000000100000001030000000100000005000000BDCE34889B994EC08006CC6FC2F1F63FBFD68897FA214EC035BE00AD58B5F43FD90B2F3D0D3B4EC06D3A4E30C47BD93FD703DB2DAEB24EC0C2ADBD9DB536E13FBDCE34889B994EC08006CC6FC2F1F63F', 1138, 1138, 3744, 0.896100000000000008, -60.7856999999999985, 'N 00 53 45', 'O 60 47 08', 175, 99);
INSERT INTO bdc.mux_grid VALUES ('176/100', '0106000020E610000001000000010300000001000000050000004064E2B9372E4FC0D60D24BEB136E13FA4D8EF8996B64EC0E1AC07B6B77BD93F0DF6CE9AA7CF4EC03F59525307DEDFBFAB81C1CA48474FC085EA118D5BECD6BF4064E2B9372E4FC0D60D24BEB136E13F', 1139, 1139, 3745, 0, -61.9466999999999999, 'N 00 00 00', 'O 61 56 48', 176, 100);
INSERT INTO bdc.mux_grid VALUES ('176/101', '0106000020E610000001000000010300000001000000050000007F2936C048474FC0A075E2565CECD6BF394E5AA5A7CF4EC053CE818906DEDFBF63E67D3CB9E84EC056FDAB51EE4DF6BFA7C159575A604FC02E2704C58311F4BF7F2936C048474FC0A075E2565CECD6BF', 1140, 1140, 3747, -0.896100000000000008, -62.1424999999999983, 'S 00 53 45', 'O 62 08 33', 176, 101);
INSERT INTO bdc.mux_grid VALUES ('176/102', '0106000020E61000000100000001030000000100000005000000DE0DDCA95A604FC074BC373A8211F4BFEE317EF8B9E84EC0E8251ACEEA4DF6BF97563531CE014FC0F95A579B245202C0873293E26E794FC042266651F03301C0DE0DDCA95A604FC074BC373A8211F4BF', 1141, 1141, 3749, -1.79220000000000002, -62.3384, 'S 01 47 31', 'O 62 20 18', 176, 102);
INSERT INTO bdc.mux_grid VALUES ('176/103', '0106000020E610000001000000010300000001000000050000004A4B4A926F794FC0C4FB01ADEE3301C08C01049FCF014FC0C3A42930215202C09826E995E81A4FC099F73AA7437D09C056702F8988924FC09A4E1324115F08C04A4B4A926F794FC0C4FB01ADEE3301C0', 1142, 1142, 3750, -2.68829999999999991, -62.5345000000000013, 'S 02 41 17', 'O 62 32 04', 176, 103);
INSERT INTO bdc.mux_grid VALUES ('176/104', '0106000020E6100000010000000103000000010000000500000004D96E9689924FC0CA61E99F0E5F08C09E6334B6EA1A4FC003B407913E7D09C02997368A0A344FC0AAF04658275410C08E0C716AA9AB4FC0198F6FBF1E8A0FC004D96E9689924FC0CA61E99F0E5F08C0', 1143, 1143, 3751, -3.58429999999999982, -62.7306999999999988, 'S 03 35 03', 'O 62 43 50', 176, 104);
INSERT INTO bdc.mux_grid VALUES ('176/105', '0106000020E6100000010000000103000000010000000500000040F9B8D5AAAB4FC035274D5A1B8A0FC0F010025E0D344FC03FE973F6235410C0E8997031364D4FC0E4BCD50CA0E913C0398227A9D3C44FC03E6788C3895A13C040F9B8D5AAAB4FC035274D5A1B8A0FC0', 1144, 1144, 3752, -4.48029999999999973, -62.9271999999999991, 'S 04 28 49', 'O 62 55 37', 176, 105);
INSERT INTO bdc.mux_grid VALUES ('176/106', '0106000020E61000000100000001030000000100000005000000DC5B2573D5C44FC0A785AB9F875A13C0D97B16BA394D4FC0BE36ABD29BE913C04CF5AFB36D664FC0A6E66221097F17C050D5BE6C09DE4FC08F3563EEF4EF16C0DC5B2573D5C44FC0A785AB9F875A13C0', 1145, 1145, 3753, -5.37619999999999987, -63.1240000000000023, 'S 05 22 34', 'O 63 07 26', 176, 106);
INSERT INTO bdc.mux_grid VALUES ('176/107', '0106000020E6100000010000000103000000010000000500000053EC4D960BDE4FC0BD4C3458F2EF16C0514EE2F271664FC017A6D90C047F17C0CB5AE83EB37F4FC0A85CB3C45F141BC0CCF853E24CF74FC04E030E104E851AC053EC4D960BDE4FC0BD4C3458F2EF16C0', 1146, 1146, 3755, -6.27210000000000001, -63.3211999999999975, 'S 06 16 19', 'O 63 19 16', 176, 107);
INSERT INTO bdc.mux_grid VALUES ('176/108', '0106000020E6100000010000000103000000010000000500000013687E6C4FF74FC0AEC04E064B851AC0E2DAB236B87F4FC07AEE58D359141BC05B94030809994FC00C28F423A1A91EC0C490E71E500850C041FAE956921A1EC013687E6C4FF74FC0AEC04E064B851AC0', 1147, 1147, 3756, -7.16790000000000038, -63.5187999999999988, 'S 07 10 04', 'O 63 31 07', 176, 108);
INSERT INTO bdc.mux_grid VALUES ('176/109', '0106000020E610000001000000010300000001000000050000007E71E794510850C071C722D88E1A1EC09AA9CDBA0E994FC0455AE8529AA91EC0E0FB034C71B24FC07BB23835651F21C0A29A82DD021550C00EE9D577DFD720C07E71E794510850C071C722D88E1A1EC0', 1148, 1148, 3758, -8.06359999999999921, -63.7169999999999987, 'S 08 03 49', 'O 63 43 01', 176, 109);
INSERT INTO bdc.mux_grid VALUES ('176/110', '0106000020E6100000010000000103000000010000000500000044B52285041550C0D925157DDDD720C07F5193BC77B24FC036A5315B611F21C043792F51EECB4FC00A8DA360ECE922C026C970CFBF2150C0AC0D878268A222C044B52285041550C0D925157DDDD720C0', 1149, 1149, 3760, -8.95919999999999916, -63.9157999999999973, 'S 08 57 33', 'O 63 54 56', 176, 110);
INSERT INTO bdc.mux_grid VALUES ('176/111', '0106000020E610000001000000010300000001000000050000003A0180A9C12150C026A4714B66A222C0F4DDAA82F5CB4FC037C93813E8E922C04556446882E54FC0F68D85A764B424C062BD4C1C882E50C0E568BEDFE26C24C03A0180A9C12150C026A4714B66A222C0', 1150, 1150, 3761, -9.85479999999999912, -64.1152000000000015, 'S 09 51 17', 'O 64 06 54', 176, 111);
INSERT INTO bdc.mux_grid VALUES ('176/112', '0106000020E61000000100000001030000000100000005000000C824B4298A2E50C0028B3D6BE06C24C0EA0D375E8AE54FC0956D98E45FB424C04045B9ED2FFF4FC03373B79BCC7E26C0744075F15C3B50C0A0905C224D3726C0C824B4298A2E50C0028B3D6BE06C24C0', 1151, 1151, 3762, -10.7501999999999995, -64.3153999999999968, 'S 10 45 00', 'O 64 18 55', 176, 112);
INSERT INTO bdc.mux_grid VALUES ('176/113', '0106000020E61000000100000001030000000100000005000000621039335F3B50C0F1F4386F4A3726C0A3CC16AC38FF4FC009FAEA60C77E26C03A0885A57C0C50C0414D6CCD224928C048B2B2823F4850C02B48BADBA50128C0621039335F3B50C0F1F4386F4A3726C0', 1152, 1152, 3763, -11.6454000000000004, -64.5164000000000044, 'S 11 38 43', 'O 64 30 59', 176, 113);
INSERT INTO bdc.mux_grid VALUES ('176/114', '0106000020E610000001000000010300000001000000050000004C64F3F9414850C0B6D99AE8A20128C0FC2C196B810C50C00FA022181D4928C01C3E097C701950C089F4F8CA65132AC06C75E30A315550C0332E719BEBCB29C04C64F3F9414850C0B6D99AE8A20128C0', 1153, 1153, 3764, -12.5404999999999998, -64.7182999999999993, 'S 12 32 25', 'O 64 43 05', 176, 114);
INSERT INTO bdc.mux_grid VALUES ('176/115', '0106000020E61000000100000001030000000100000005000000A4FDDEB8335550C08B94D966E8CB29C068566BAA751950C08D8350985F132AC004813CBE742650C027F3952094DD2BC03E28B0CC326250C027041FEF1C962BC0A4FDDEB8335550C08B94D966E8CB29C0', 1154, 1154, 3766, -13.4354999999999993, -64.9210999999999956, 'S 13 26 07', 'O 64 55 15', 176, 115);
INSERT INTO bdc.mux_grid VALUES ('176/116', '0106000020E610000001000000010300000001000000050000001254C3B2356250C0FCFF6D7719962BC0905B10587A2650C0C452666D8DDD2BC0F89395B88A3350C011481B58ACA72DC07E8C4813466F50C047F5226238602DC01254C3B2356250C0FCFF6D7719962BC0', 1155, 1155, 3767, -14.3302999999999994, -65.1248999999999967, 'S 14 19 49', 'O 65 07 29', 176, 116);
INSERT INTO bdc.mux_grid VALUES ('176/117', '0106000020E610000001000000010300000001000000050000000087F032496F50C0AA8F90A534602DC01228BDC0903350C089B1F120A5A72DC024ADF6C0B34050C0B462B5F8AC712FC0130C2A336C7C50C0D440547D3C2A2FC00087F032496F50C0AA8F90A534602DC0', 1156, 1156, 3768, -15.2249999999999996, -65.329899999999995, 'S 15 13 29', 'O 65 19 47', 176, 117);
INSERT INTO bdc.mux_grid VALUES ('176/118', '0106000020E610000001000000010300000001000000050000005A0C068E6F7C50C088C8EF79382A2FC07056953ABA4050C001D6D039A5712FC00E2A8037F14D50C0E9534943CA9D30C0F8DFF08AA68950C02ACD58E3137A30C05A0C068E6F7C50C088C8EF79382A2FC0', 1157, 1157, 3771, -16.1193999999999988, -65.5361000000000047, 'S 16 07 09', 'O 65 32 09', 176, 118);
INSERT INTO bdc.mux_grid VALUES ('176/119', '0106000020E610000001000000010300000001000000050000006A04C422AA8950C093B52FBD117A30C0E238FE25F84D50C023D4EF1DC69D30C03C256F87445B50C0BF6044C1B08231C0C4F03484F69650C030428460FC5E31C06A04C422AA8950C093B52FBD117A30C0', 1158, 1158, 3772, -17.0137, -65.7434999999999974, 'S 17 00 49', 'O 65 44 36', 176, 119);
INSERT INTO bdc.mux_grid VALUES ('176/120', '0106000020E61000000100000001030000000100000005000000AC49E85AFA9650C00ECBBF14FA5E31C00ECC7DEE4B5B50C08151CE53AC8231C068220928AF6850C0E77ED834896732C006A073945DA450C073F8C9F5D64332C0AC49E85AFA9650C00ECBBF14FA5E31C0', 1159, 1159, 3773, -17.9076999999999984, -65.9523999999999972, 'S 17 54 27', 'O 65 57 08', 176, 120);
INSERT INTO bdc.mux_grid VALUES ('176/121', '0106000020E61000000100000001030000000100000005000000BC6F18AC61A450C008932D83D44332C04CC6A60BB76850C0DB5DE27C846732C0021D969D327650C0976C7DDA524C33C070C6073EDDB150C0C4A1C8E0A22833C0BC6F18AC61A450C008932D83D44332C0', 1160, 1160, 3774, -18.8016000000000005, -66.162700000000001, 'S 18 48 05', 'O 66 09 45', 176, 121);
INSERT INTO bdc.mux_grid VALUES ('176/122', '0106000020E6100000010000000103000000010000000500000080F9D998E1B150C09A3AFE45A02833C0E61313023B7650C0D5B472D54D4C33C098666A7AD08350C0E7DE59EC0C3134C0304C311177BF50C0AC64E55C5F0D34C080F9D998E1B150C09A3AFE45A02833C0', 1161, 1161, 3776, -19.6951000000000001, -66.3744999999999976, 'S 19 41 42', 'O 66 22 28', 176, 122);
INSERT INTO bdc.mux_grid VALUES ('176/123', '0106000020E610000001000000010300000001000000050000007A309AB17BBF50C0CEC37B985C0D34C03E2A6E64D98350C0E8EC7197073134C0FCE001608A9150C0628E01A2B61535C03AE72DAD2CCD50C048650BA30BF234C07A309AB17BBF50C0CEC37B985C0D34C0', 1162, 1162, 3777, -20.5884999999999998, -66.5879999999999939, 'S 20 35 18', 'O 66 35 16', 176, 123);
INSERT INTO bdc.mux_grid VALUES ('176/124', '0106000020E61000000100000001030000000100000005000000FE26C79531CD50C0DD6574B308F234C0CFC590D4939150C005353CFAB01535C0DC492E00629F50C067CB2C304FFA35C00EAB64C1FFDA50C040FC64E9A6D635C0FE26C79531CD50C0DD6574B308F234C0', 1163, 1163, 3778, -21.4816000000000003, -66.803299999999993, 'S 21 28 53', 'O 66 48 11', 176, 124);
INSERT INTO bdc.mux_grid VALUES ('176/125', '0106000020E610000001000000010300000001000000050000004690FBF404DB50C0F198F3CCA3D635C0E0BFAF046C9F50C075964E3249FA35C01A705A1E59AD50C0CE1769C8D5DE36C08040A60EF2E850C04C1A0E6330BB36C04690FBF404DB50C0F198F3CCA3D635C0', 1164, 1164, 3779, -22.3744000000000014, -67.0203999999999951, 'S 22 22 27', 'O 67 01 13', 176, 125);
INSERT INTO bdc.mux_grid VALUES ('176/126', '0106000020E61000000100000001030000000100000005000000284D3F90F7E850C0C846F4172DBB36C054E29FB863AD50C0932FF770CFDE36C02A65E49071BB50C03111C29849C337C0FECF836805F750C06528BF3FA79F37C0284D3F90F7E850C0C846F4172DBB36C0', 1165, 1165, 3781, -23.2669999999999995, -67.2395000000000067, 'S 23 16 01', 'O 67 14 22', 176, 126);
INSERT INTO bdc.mux_grid VALUES ('176/127', '0106000020E6100000010000000103000000010000000500000040AC5E3B0BF750C09D770BC4A39F37C094C030C77CBB50C007BAFDE342C337C05EE59042ADC950C0DCF961CBA9A738C008D1BEB63B0551C072B76FAB0A8438C040AC5E3B0BF750C09D770BC4A39F37C0', 1166, 1166, 3782, -24.1593000000000018, -67.4605999999999995, 'S 24 09 33', 'O 67 27 38', 176, 127);
INSERT INTO bdc.mux_grid VALUES ('176/128', '0106000020E610000001000000010300000001000000050000005E9F5ADE410551C0CBC40AFD068438C0CADCA01BB9C950C091A243B5A2A738C058771A340ED850C0DC122986F58B39C0EE39D4F6961351C01535F0CD596839C05E9F5ADE410551C0CBC40AFD068438C0', 1167, 1167, 3783, -25.0512000000000015, -67.6839999999999975, 'S 25 03 04', 'O 67 41 02', 176, 128);
INSERT INTO bdc.mux_grid VALUES ('176/129', '0106000020E610000001000000010300000001000000050000001E54F4769D1351C0E6CE99EA556839C02E942DB71AD850C0A8E85A0AEE8B39C05CFEDE7D96E650C07CEF3AEA2B703AC04CBEA53D192251C0B9D579CA934C3AC01E54F4769D1351C0E6CE99EA556839C0', 1168, 1168, 3784, -25.9429000000000016, -67.9097000000000008, 'S 25 56 34', 'O 67 54 34', 176, 129);
INSERT INTO bdc.mux_grid VALUES ('176/130', '0106000020E61000000100000001030000000100000005000000AAED561A202251C00DDEC5AF8F4C3AC09696C1B2A3E650C0CAE8120424703AC0B4CAAE5148F550C018BF80134C543BC0C82144B9C43051C05BB433BFB7303BC0AAED561A202251C00DDEC5AF8F4C3AC0', 1169, 1169, 3785, -26.8341999999999992, -68.1379000000000019, 'S 26 50 03', 'O 68 08 16', 176, 130);
INSERT INTO bdc.mux_grid VALUES ('176/131', '0106000020E61000000100000001030000000100000005000000825AE2F6CB3051C058B3866AB3303BC080F0C44056F550C01011FABD43543BC0A082C0FC250451C076891F1855383CC0A2ECDDB29B3F51C0BE2BACC4C4143CC0825AE2F6CB3051C058B3866AB3303BC0', 1170, 1170, 3786, -27.7251000000000012, -68.3686000000000007, 'S 27 43 30', 'O 68 22 07', 176, 131);
INSERT INTO bdc.mux_grid VALUES ('176/132', '0106000020E61000000100000001030000000100000005000000729B1A56A33F51C0818A3733C0143CC03C0C12AF340451C0E075D34D4C383CC090A2CDE9311351C0362BE107461C3DC0C531D690A04E51C0D73F45EDB9F83CC0729B1A56A33F51C0818A3733C0143CC0', 1171, 1171, 3787, -28.6157000000000004, -68.602099999999993, 'S 28 36 56', 'O 68 36 07', 176, 132);
INSERT INTO bdc.mux_grid VALUES ('176/133', '0106000020E610000001000000010300000001000000050000002A2FBF9EA84E51C02C20031CB5F83CC02C661369411351C01316FFC23C1C3DC01CB85BA36E2251C062BA8EEB1D003EC01A8107D9D55D51C07BC4924496DC3DC02A2FBF9EA84E51C02C20031CB5F83CC0', 1172, 1172, 3788, -29.5060000000000002, -68.8384999999999962, 'S 29 30 21', 'O 68 50 18', 176, 133);
INSERT INTO bdc.mux_grid VALUES ('176/134', '0106000020E6100000010000000103000000010000000500000022B60E57DE5D51C09D6E413091DC3DC0561E0EFA7E2251C0C072D32514003EC0BCF736D6DE3151C0CAEC3AC4DBE33EC0888F37333E6D51C0A8E8A8CE58C03EC022B60E57DE5D51C09D6E413091DC3DC0', 1173, 1173, 3789, -30.3958000000000013, -69.078000000000003, 'S 30 23 44', 'O 69 04 40', 176, 134);
INSERT INTO bdc.mux_grid VALUES ('176/135', '0106000020E610000001000000010300000001000000050000000C683B27476D51C0DEBDC57353C03EC0260C9E0FF03151C0FA10E776D1E33EC0AC532354854151C09CCA7A8A7EC73FC092AFC06BDC7C51C07E77598700A43FC00C683B27476D51C0DEBDC57353C03EC0', 1174, 1174, 3791, -31.2852999999999994, -69.3205999999999989, 'S 31 17 06', 'O 69 19 14', 176, 135);
INSERT INTO bdc.mux_grid VALUES ('176/136', '0106000020E61000000100000001030000000100000005000000B46A15DCE57C51C0FE5F1BE2FAA33FC0B67B687C974151C0BD2F48AE73C73FC02ED3C916655151C0BA77C596825540C02EC27676B38C51C0DA0FAF30C64340C0B46A15DCE57C51C0FE5F1BE2FAA33FC0', 1175, 1175, 3793, -32.1743000000000023, -69.5666999999999973, 'S 32 10 27', 'O 69 33 59', 176, 136);
INSERT INTO bdc.mux_grid VALUES ('176/137', '0106000020E610000001000000010300000001000000050000008CBFF069BD8C51C0A0B0D736C34340C0F4620B3B785151C0A87550DD7C5540C07E9FE842816151C0F0A02F4937C740C014FCCD71C69C51C0E8DBB6A27DB540C08CBFF069BD8C51C0A0B0D736C34340C0', 1176, 1176, 3794, -33.0628999999999991, -69.8162999999999982, 'S 33 03 46', 'O 69 48 58', 176, 137);
INSERT INTO bdc.mux_grid VALUES ('176/138', '0106000020E610000001000000010300000001000000050000008E20CDEFD09C51C09492727F7AB540C0F87A4F71956151C082DD224031C740C0E0F2CC2BDD7151C0EC694DC9DC3841C076984AAA18AD51C0FE1E9D08262741C08E20CDEFD09C51C09492727F7AB540C0', 1177, 1177, 3795, -33.9510000000000005, -70.0696999999999974, 'S 33 57 03', 'O 70 04 10', 176, 138);
INSERT INTO bdc.mux_grid VALUES ('176/139', '0106000020E6100000010000000103000000010000000500000008EFC6BA23AD51C0A2D489B9222741C06A81A473F27151C016F7156CD63841C0D6091F577C8251C0C8B4B67D72AA41C07277419EADBD51C052922ACBBE9841C008EFC6BA23AD51C0A2D489B9222741C0', 1178, 1178, 3796, -34.8387000000000029, -70.3271000000000015, 'S 34 50 19', 'O 70 19 37', 176, 139);
INSERT INTO bdc.mux_grid VALUES ('176/140', '0106000020E610000001000000010300000001000000050000004031D949B9BD51C0D47FB44DBB9841C012C0EFC8928251C06ED362C76BAA41C08C2A0981629351C03ED829C6F71B42C0BA9BF20189CE51C0A4847B4C470A42C04031D949B9BD51C0D47FB44DBB9841C0', 1179, 1179, 3798, -35.7257999999999996, -70.5887000000000029, 'S 35 43 33', 'O 70 35 19', 176, 140);
INSERT INTO bdc.mux_grid VALUES ('176/141', '0106000020E61000000100000001030000000100000005000000169EF95195CE51C0F08BD89D430A42C030FCB52E7A9351C0FE2960B1F01B42C02E02C4A093A451C03B79DBFA6B8D42C014A407C4AEDF51C02CDB53E7BE7B42C0169EF95195CE51C0F08BD89D430A42C0', 1180, 1180, 3799, -36.6124999999999972, -70.854699999999994, 'S 36 36 45', 'O 70 51 16', 176, 141);
INSERT INTO bdc.mux_grid VALUES ('176/142', '0106000020E6100000010000000103000000010000000500000046D398C2BBDF51C04E5B7E04BB7B42C05219AB9DACA451C0AE37D181648D42C0FAE393ED13B651C04439B46BCEFE42C0EE9D811223F151C0E45C61EE24ED42C046D398C2BBDF51C04E5B7E04BB7B42C0', 1181, 1181, 3800, -37.4986000000000033, -71.1253999999999991, 'S 37 29 55', 'O 71 07 31', 176, 142);
INSERT INTO bdc.mux_grid VALUES ('176/143', '0106000020E61000000100000001030000000100000005000000A02192CA30F151C0FE6E12D420ED42C01C04B34E2EB651C050542288C6FE42C0B2F743E4E7C751C0CC3B7A5F1E7043C038152360EA0252C078566AAB785E43C0A02192CA30F151C0FE6E12D420ED42C0', 1182, 1182, 3802, -38.3841999999999999, -71.4010999999999996, 'S 38 23 03', 'O 71 24 03', 176, 143);
INSERT INTO bdc.mux_grid VALUES ('176/144', '0106000020E61000000100000001030000000100000005000000C2D197DDF80252C0B4611356745E43C0DA0661C003C851C0403A910A167043C0381B2E4D14DA51C0240BE4125BE143C020E6646A091552C09632665EB9CF43C0C2D197DDF80252C0B4611356745E43C0', 1183, 1183, 3804, -39.2691999999999979, -71.6820000000000022, 'S 39 16 09', 'O 71 40 55', 176, 144);
INSERT INTO bdc.mux_grid VALUES ('176/145', '0106000020E61000000100000001030000000100000005000000F27A2ABA181552C03CBF29CAB4CF43C03B5A04BD31DA51C0CA843E4552E143C02A36E0429EEC51C08C2F92B7835244C0E4560640852752C0FE697D3CE64044C0F27A2ABA181552C03CBF29CAB4CF43C0', 1184, 1184, 3806, -40.1535999999999973, -71.9684000000000026, 'S 40 09 13', 'O 71 58 06', 176, 145);
INSERT INTO bdc.mux_grid VALUES ('176/91', '0106000020E6100000010000000103000000010000000500000016D82566684B4EC05C29B4B7DC3321406820647CD5D34DC0C7FD21E357EC204044586BCD41ED4DC023314C588B431E40F50F2DB7D4644EC04D88700195D21E4016D82566684B4EC05C29B4B7DC332140', 1185, 1185, 3841, 8.06359999999999921, -60.1762999999999977, 'N 08 03 49', 'O 60 10 34', 176, 91);
INSERT INTO bdc.mux_grid VALUES ('176/92', '0106000020E61000000100000001030000000100000005000000D6343351D1644EC0BFC4BFF090D21E401EF392733BED4DC04B166ABF83431E4076A1AEE394064EC01C33A3BE46AE1A4031E34EC12A7E4EC08FE1F8EF533D1B40D6343351D1644EC0BFC4BFF090D21E40', 1186, 1186, 3842, 7.16790000000000038, -60.3744999999999976, 'N 07 10 04', 'O 60 22 28', 176, 92);
INSERT INTO bdc.mux_grid VALUES ('176/93', '0106000020E61000000100000001030000000100000005000000DE36EFBE277E4EC022C86D56503D1B40D93A42478F064EC0629F580840AE1A40DA193E15D81F4EC0E4A9994BED181740DE15EB8C70974EC0A4D2AE99FDA71740DE36EFBE277E4EC022C86D56503D1B40', 1187, 1187, 3844, 6.27210000000000001, -60.5722000000000023, 'N 06 16 19', 'O 60 34 19', 176, 93);
INSERT INTO bdc.mux_grid VALUES ('176/94', '0106000020E61000000100000001030000000100000005000000C11AAFEC6D974EC065698975FAA71740295F8333D31F4EC0B442A374E7181740B1F4DE950D394EC0FD89A4D08183134048B00A4FA8B04EC0AEB08AD194121440C11AAFEC6D974EC065698975FAA71740', 1188, 1188, 3846, 5.37619999999999987, -60.7693999999999974, 'N 05 22 34', 'O 60 46 09', 176, 94);
INSERT INTO bdc.mux_grid VALUES ('176/95', '0106000020E61000000100000001030000000100000005000000FA5EAD0FA6B04EC08628462192121440CE7D796C09394EC0164D2FD67C831340E63C8C9237524EC084E6AA3B0EDC0F40121EC035D4C94EC0AF4EEC681C7D1040FA5EAD0FA6B04EC08628462192121440', 1189, 1189, 3847, 4.48029999999999973, -60.9662000000000006, 'N 04 28 49', 'O 60 57 58', 176, 95);
INSERT INTO bdc.mux_grid VALUES ('176/96', '0106000020E610000001000000010300000001000000050000006D912C56D2C94EC0B96C3D2B1A7D1040F9187B1F34524EC0D590F7FA05DC0F40E2029132586B4EC05F993A0400B10840547B4269F6E24EC0FCE1BD5F2ECF09406D912C56D2C94EC0B96C3D2B1A7D1040', 1190, 1190, 3848, 3.58429999999999982, -61.162700000000001, 'N 03 35 03', 'O 61 09 45', 176, 96);
INSERT INTO bdc.mux_grid VALUES ('176/97', '0106000020E6100000010000000103000000010000000500000096D092E8F4E24EC0846C65C72ACF094062A72C74556B4EC0DF19C973F9B00840BD9F9C9871844EC091641597DE850140F1C8020D11FC4EC037B7B1EA0FA4024096D092E8F4E24EC0846C65C72ACF0940', 1191, 1191, 3849, 2.68829999999999991, -61.3588999999999984, 'N 02 41 17', 'O 61 21 32', 176, 97);
INSERT INTO bdc.mux_grid VALUES ('176/98', '0106000020E610000001000000010300000001000000050000003C327FEA0FFC4EC0CAD1A6330DA402407D35958D6F844EC03F3FC2B3D98501406332D2E3859D4EC08612141E5FB5F43F202FBC4026154FC09D37DD1DC6F1F63F3C327FEA0FFC4EC0CAD1A6330DA40240', 1192, 1192, 3850, 1.79220000000000002, -61.5549000000000035, 'N 01 47 31', 'O 61 33 17', 176, 98);
INSERT INTO bdc.mux_grid VALUES ('176/99', '0106000020E610000001000000010300000001000000050000006336DA7B25154FC06A06CC6FC2F1F63F633E2E8B849D4EC019BE00AD58B5F43F7B73D43097B64EC0893A4E30C47BD93F7B6B8021382E4FC0E9ADBD9DB536E13F6336DA7B25154FC06A06CC6FC2F1F63F', 1193, 1193, 3852, 0.896100000000000008, -61.7507999999999981, 'N 00 53 45', 'O 61 45 03', 176, 99);
INSERT INTO bdc.mux_grid VALUES ('177/100', '0106000020E61000000100000001030000000100000005000000E2CB87ADC1A94FC0E50D24BEB136E13F4840957D20324FC030AD07B6B77BD93FB25D748E314B4FC02659525307DEDFBF4DE966BED2C24FC08CEA118D5BECD6BFE2CB87ADC1A94FC0E50D24BEB136E13F', 1194, 1194, 3853, 0, -62.9117999999999995, 'N 00 00 00', 'O 62 54 42', 177, 100);
INSERT INTO bdc.mux_grid VALUES ('177/101', '0106000020E610000001000000010300000001000000050000001F91DBB3D2C24FC0A775E2565CECD6BFDCB5FF98314B4FC006CE818906DEDFBF064E233043644FC0D3FDAB51EE4DF6BF4929FF4AE4DB4FC0C42704C58311F4BF1F91DBB3D2C24FC0A775E2565CECD6BF', 1195, 1195, 3856, -0.896100000000000008, -63.1077000000000012, 'S 00 53 45', 'O 63 06 27', 177, 101);
INSERT INTO bdc.mux_grid VALUES ('177/102', '0106000020E610000001000000010300000001000000050000007F75819DE4DB4FC013BD373A8211F4BF949923EC43644FC06D261ACEEA4DF6BF3BBEDA24587D4FC0325B579B245202C0269A38D6F8F44FC085266651F03301C07F75819DE4DB4FC013BD373A8211F4BF', 1196, 1196, 3857, -1.79220000000000002, -63.303600000000003, 'S 01 47 31', 'O 63 18 12', 177, 102);
INSERT INTO bdc.mux_grid VALUES ('177/103', '0106000020E61000000100000001030000000100000005000000F7B2EF85F9F44FC0E9FB01ADEE3301C03069A992597D4FC0FEA42930215202C03A8E8E8972964FC0ADF73AA7437D09C0006C6A3E090750C0974E1324115F08C0F7B2EF85F9F44FC0E9FB01ADEE3301C0', 1197, 1197, 3858, -2.68829999999999991, -63.4996000000000009, 'S 02 41 17', 'O 63 29 58', 177, 103);
INSERT INTO bdc.mux_grid VALUES ('177/104', '0106000020E6100000010000000103000000010000000500000050200AC5090750C0E061E99F0E5F08C049CBD9A974964FC004B407913E7D09C0D5FEDB7D94AF4FC0F7F04658275410C0183A0BAF991350C0C68F6FBF1E8A0FC050200AC5090750C0E061E99F0E5F08C0', 1198, 1198, 3859, -3.58429999999999982, -63.6957999999999984, 'S 03 35 03', 'O 63 41 45', 177, 104);
INSERT INTO bdc.mux_grid VALUES ('177/105', '0106000020E610000001000000010300000001000000050000006E30AF649A1350C0F1274D5A1B8A0FC08E78A75197AF4FC09DE973F6235410C087011625C0C84FC049BDD50CA0E913C0ED7466CE2E2050C0A46788C3895A13C06E30AF649A1350C0F1274D5A1B8A0FC0', 1199, 1199, 3860, -4.48029999999999973, -63.8922999999999988, 'S 04 28 49', 'O 63 53 32', 177, 105);
INSERT INTO bdc.mux_grid VALUES ('177/106', '0106000020E61000000100000001030000000100000005000000BC6165B32F2050C00E86AB9F875A13C082E3BBADC3C84FC01737ABD29BE913C0F45C55A7F7E14FC0EAE66221097F17C0761E32B0C92C50C0E43563EEF4EF16C0BC6165B32F2050C00E86AB9F875A13C0', 1200, 1200, 3862, -5.37619999999999987, -64.089100000000002, 'S 05 22 34', 'O 64 05 20', 177, 106);
INSERT INTO bdc.mux_grid VALUES ('177/107', '0106000020E61000000100000001030000000100000005000000FCA9F9C4CA2C50C0034D3458F2EF16C0FCB587E6FBE14FC058A6D90C047F17C072C28D323DFB4FC07F5CB3C45F141BC038B0FC6A6B3950C027030E104E851AC0FCA9F9C4CA2C50C0034D3458F2EF16C0', 1201, 1201, 3863, -6.27210000000000001, -64.2862999999999971, 'S 06 16 19', 'O 64 17 10', 177, 107);
INSERT INTO bdc.mux_grid VALUES ('177/108', '0106000020E61000000100000001030000000100000005000000D6E711B06C3950C092C04E064B851AC09442582A42FB4FC046EE58D359141BC0087ED47D490A50C04128F423A1A91EC09644BA18154650C08EFAE956921A1EC0D6E711B06C3950C092C04E064B851AC0', 1202, 1202, 3864, -7.16790000000000038, -64.4839999999999947, 'S 07 10 04', 'O 64 29 02', 177, 108);
INSERT INTO bdc.mux_grid VALUES ('177/109', '0106000020E610000001000000010300000001000000050000005825BA8E164650C0A5C722D88E1A1EC09E8839574C0A50C0915AE8529AA91EC0C0B1D49FFD1650C074B23835651F21C07C4E55D7C75250C0FDE8D577DFD720C05825BA8E164650C0A5C722D88E1A1EC0', 1203, 1203, 3867, -8.06359999999999921, -64.6821999999999946, 'S 08 03 49', 'O 64 40 55', 177, 109);
INSERT INTO bdc.mux_grid VALUES ('177/110', '0106000020E610000001000000010300000001000000050000001469F57EC95250C0D225157DDDD720C09A5C1CD8001750C025A5315B611F21C07E706A22BC2350C05A8DA360ECE922C0F87C43C9845F50C00A0E878268A222C01469F57EC95250C0D225157DDDD720C0', 1204, 1204, 3868, -8.95919999999999916, -64.8810000000000002, 'S 08 57 33', 'O 64 52 51', 177, 110);
INSERT INTO bdc.mux_grid VALUES ('177/111', '0106000020E6100000010000000103000000010000000500000018B552A3865F50C077A4714B66A222C0D42228BBBF2350C08CC93813E8E922C0FADEF42D863050C0E88D85A764B424C040711F164D6C50C0D168BEDFE26C24C018B552A3865F50C077A4714B66A222C0', 1205, 1205, 3869, -9.85479999999999912, -65.0803999999999974, 'S 09 51 17', 'O 65 04 49', 177, 111);
INSERT INTO bdc.mux_grid VALUES ('177/112', '0106000020E610000001000000010300000001000000050000009AD886234F6C50C0FC8A3D6BE06C24C0C63AEE288A3050C08F6D98E45FB424C07256AFF05C3D50C04A73B79BCC7E26C046F447EB217950C0B7905C224D3726C09AD886234F6C50C0FC8A3D6BE06C24C0', 1206, 1206, 3870, -10.7501999999999995, -65.2806000000000068, 'S 10 45 00', 'O 65 16 50', 177, 112);
INSERT INTO bdc.mux_grid VALUES ('177/113', '0106000020E6100000010000000103000000010000000500000032C40B2D247950C006F5386F4A3726C01C1ADE4F613D50C027FAEA60C77E26C002BC579F414A50C0444D6CCD224928C01A66857C048650C02348BADBA50128C032C40B2D247950C006F5386F4A3726C0', 1207, 1207, 3871, -11.6454000000000004, -65.4814999999999969, 'S 11 38 43', 'O 65 28 53', 177, 113);
INSERT INTO bdc.mux_grid VALUES ('177/114', '0106000020E610000001000000010300000001000000050000001218C6F3068650C0B6D99AE8A20128C0CAE0EB64464A50C007A022181D4928C0E8F1DB75355750C05DF4F8CA65132AC03229B604F69250C00C2E719BEBCB29C01218C6F3068650C0B6D99AE8A20128C0', 1208, 1208, 3873, -12.5404999999999998, -65.683400000000006, 'S 12 32 25', 'O 65 41 00', 177, 114);
INSERT INTO bdc.mux_grid VALUES ('177/115', '0106000020E6100000010000000103000000010000000500000076B1B1B2F89250C05A94D966E8CB29C0300A3EA43A5750C06B8350985F132AC0CA340FB8396450C024F3952094DD2BC010DC82C6F79F50C014041FEF1C962BC076B1B1B2F89250C05A94D966E8CB29C0', 1209, 1209, 3874, -13.4354999999999993, -65.8862000000000023, 'S 13 26 07', 'O 65 53 10', 177, 115);
INSERT INTO bdc.mux_grid VALUES ('177/116', '0106000020E61000000100000001030000000100000005000000E20796ACFA9F50C0EDFF6D7719962BC05C0FE3513F6450C0BC52666D8DDD2BC0C44768B24F7150C0A2471B58ACA72DC04A401B0D0BAD50C0D2F4226238602DC0E20796ACFA9F50C0EDFF6D7719962BC0', 1210, 1210, 3875, -14.3302999999999994, -66.0901000000000067, 'S 14 19 49', 'O 66 05 24', 177, 116);
INSERT INTO bdc.mux_grid VALUES ('177/117', '0106000020E61000000100000001030000000100000005000000B83AC32C0EAD50C0508F90A534602DC0ECDB8FBA557150C005B1F120A5A72DC00661C9BA787E50C04E63B5F8AC712FC0D3BFFC2C31BA50C09941547D3C2A2FC0B83AC32C0EAD50C0508F90A534602DC0', 1211, 1211, 3876, -15.2249999999999996, -66.295100000000005, 'S 15 13 29', 'O 66 17 42', 177, 117);
INSERT INTO bdc.mux_grid VALUES ('177/118', '0106000020E610000001000000010300000001000000050000002EC0D88734BA50C031C9EF79382A2FC0320A68347F7E50C0C2D6D039A5712FC0CEDD5231B68B50C01B544943CA9D30C0CA93C3846BC750C054CD58E3137A30C02EC0D88734BA50C031C9EF79382A2FC0', 1212, 1212, 3879, -16.1193999999999988, -66.5011999999999972, 'S 16 07 09', 'O 66 30 04', 177, 118);
INSERT INTO bdc.mux_grid VALUES ('177/119', '0106000020E6100000010000000103000000010000000500000034B8961C6FC750C0C2B52FBD117A30C0AAECD01FBD8B50C050D4EF1DC69D30C004D94181099950C0FD6044C1B08231C08EA4077EBBD450C06F428460FC5E31C034B8961C6FC750C0C2B52FBD117A30C0', 1213, 1213, 3880, -17.0137, -66.7086999999999932, 'S 17 00 49', 'O 66 42 31', 177, 119);
INSERT INTO bdc.mux_grid VALUES ('177/120', '0106000020E6100000010000000103000000010000000500000070FDBA54BFD450C04ECBBF14FA5E31C0D27F50E8109950C0C151CE53AC8231C02ED6DB2174A650C0367FD834896732C0CC53468E22E250C0C4F8C9F5D64332C070FDBA54BFD450C04ECBBF14FA5E31C0', 1214, 1214, 3881, -17.9076999999999984, -66.917500000000004, 'S 17 54 27', 'O 66 55 03', 177, 120);
INSERT INTO bdc.mux_grid VALUES ('177/121', '0106000020E610000001000000010300000001000000050000008823EBA526E250C053932D83D44332C03C7A79057CA650C00F5EE27C846732C0E2D06897F7B350C0DB6B7DDA524C33C0307ADA37A2EF50C01FA1C8E0A22833C08823EBA526E250C053932D83D44332C0', 1215, 1215, 3882, -18.8016000000000005, -67.1277999999999935, 'S 18 48 05', 'O 67 07 40', 177, 121);
INSERT INTO bdc.mux_grid VALUES ('177/122', '0106000020E6100000010000000103000000010000000500000048ADAC92A6EF50C0EF39FE45A02833C0AEC7E5FBFFB350C029B472D54D4C33C0701A3D7495C150C04CDF59EC0C3134C00A00040B3CFD50C01165E55C5F0D34C048ADAC92A6EF50C0EF39FE45A02833C0', 1216, 1216, 3883, -19.6951000000000001, -67.3396000000000043, 'S 19 41 42', 'O 67 20 22', 177, 122);
INSERT INTO bdc.mux_grid VALUES ('177/123', '0106000020E6100000010000000103000000010000000500000068E46CAB40FD50C024C47B985C0D34C00ADE405E9EC150C051ED7197073134C0C294D4594FCF50C05A8E01A2B61535C0209B00A7F10A51C02E650BA30BF234C068E46CAB40FD50C024C47B985C0D34C0', 1217, 1217, 3884, -20.5884999999999998, -67.5531000000000006, 'S 20 35 18', 'O 67 33 11', 177, 123);
INSERT INTO bdc.mux_grid VALUES ('177/124', '0106000020E61000000100000001030000000100000005000000C4DA998FF60A51C0D86574B308F234C0947963CE58CF50C0FE343CFAB01535C0A4FD00FA26DD50C06FCB2C304FFA35C0D45E37BBC41851C049FC64E9A6D635C0C4DA998FF60A51C0D86574B308F234C0', 1218, 1218, 3885, -21.4816000000000003, -67.7683999999999997, 'S 21 28 53', 'O 67 46 06', 177, 124);
INSERT INTO bdc.mux_grid VALUES ('177/125', '0106000020E610000001000000010300000001000000050000002444CEEEC91851C0EC98F3CCA3D635C09A7382FE30DD50C083964E3249FA35C0D4232D181EEB50C0ED1769C8D5DE36C05EF47808B72651C0571A0E6330BB36C02444CEEEC91851C0EC98F3CCA3D635C0', 1219, 1219, 3886, -22.3744000000000014, -67.9855000000000018, 'S 22 22 27', 'O 67 59 07', 177, 125);
INSERT INTO bdc.mux_grid VALUES ('177/126', '0106000020E61000000100000001030000000100000005000000F000128ABC2651C0E246F4172DBB36C01C9672B228EB50C0AC2FF770CFDE36C0F218B78A36F950C05911C29849C337C0C6835662CA3451C08E28BF3FA79F37C0F000128ABC2651C0E246F4172DBB36C0', 1220, 1220, 3889, -23.2669999999999995, -68.2045999999999992, 'S 23 16 01', 'O 68 12 16', 177, 126);
INSERT INTO bdc.mux_grid VALUES ('177/127', '0106000020E610000001000000010300000001000000050000002E603135D03451C0B0770BC4A39F37C03C7403C141F950C041BAFDE342C337C0FE98633C720751C0A6F961CBA9A738C0F08491B0004351C015B76FAB0A8438C02E603135D03451C0B0770BC4A39F37C0', 1221, 1221, 3890, -24.1593000000000018, -68.4257999999999953, 'S 24 09 33', 'O 68 25 32', 177, 127);
INSERT INTO bdc.mux_grid VALUES ('177/128', '0106000020E610000001000000010300000001000000050000001A532DD8064351C088C40AFD068438C0849073157E0751C04CA243B5A2A738C01D2BED2DD31551C026132986F58B39C0B2EDA6F05B5151C06235F0CD596839C01A532DD8064351C088C40AFD068438C0', 1222, 1222, 3891, -25.0512000000000015, -68.6491999999999933, 'S 25 03 04', 'O 68 38 56', 177, 128);
INSERT INTO bdc.mux_grid VALUES ('177/129', '0106000020E610000001000000010300000001000000050000000408C770625151C01BCF99EA556839C0164800B1DF1551C0DCE85A0AEE8B39C043B2B1775B2451C0BEEF3AEA2B703AC034727837DE5F51C0FCD579CA934C3AC00408C770625151C01BCF99EA556839C0', 1223, 1223, 3893, -25.9429000000000016, -68.8748999999999967, 'S 25 56 34', 'O 68 52 29', 177, 129);
INSERT INTO bdc.mux_grid VALUES ('177/130', '0106000020E6100000010000000103000000010000000500000078A12914E55F51C062DEC5AF8F4C3AC0644A94AC682451C01CE9120424703AC07C7E814B0D3351C0FBBE80134C543BC08ED516B3896E51C03EB433BFB7303BC078A12914E55F51C062DEC5AF8F4C3AC0', 1224, 1224, 3894, -26.8341999999999992, -69.1029999999999944, 'S 26 50 03', 'O 69 06 10', 177, 130);
INSERT INTO bdc.mux_grid VALUES ('177/131', '0106000020E610000001000000010300000001000000050000001D0EB5F0906E51C058B3866AB3303BC05EA4973A1B3351C0E510FABD43543BC0863693F6EA4151C0DB891F1855383CC044A0B0AC607D51C04D2CACC4C4143CC01D0EB5F0906E51C058B3866AB3303BC0', 1225, 1225, 3895, -27.7251000000000012, -69.3337999999999965, 'S 27 43 30', 'O 69 20 01', 177, 131);
INSERT INTO bdc.mux_grid VALUES ('177/132', '0106000020E610000001000000010300000001000000050000005C4FED4F687D51C0E28A3733C0143CC004C0E4A8F94151C05476D34D4C383CC05056A0E3F65051C03B2BE107461C3DC0A8E5A88A658C51C0C93F45EDB9F83CC05C4FED4F687D51C0E28A3733C0143CC0', 1226, 1226, 3896, -28.6157000000000004, -69.567300000000003, 'S 28 36 56', 'O 69 34 02', 177, 132);
INSERT INTO bdc.mux_grid VALUES ('177/133', '0106000020E61000000100000001030000000100000005000000EEE291986D8C51C02F20031CB5F83CC0141AE662065151C0FF15FFC23C1C3DC00E6C2E9D336051C0DBBA8EEB1D003EC0EA34DAD29A9B51C00DC5924496DC3DC0EEE291986D8C51C02F20031CB5F83CC0', 1227, 1227, 3898, -29.5060000000000002, -69.8037000000000063, 'S 29 30 21', 'O 69 48 13', 177, 133);
INSERT INTO bdc.mux_grid VALUES ('177/134', '0106000020E61000000100000001030000000100000005000000D269E150A39B51C0406F413091DC3DC04AD2E0F3436051C03A73D32514003EC0B2AB09D0A36F51C054ED3AC4DBE33EC038430A2D03AB51C059E9A8CE58C03EC0D269E150A39B51C0406F413091DC3DC0', 1228, 1228, 3899, -30.3958000000000013, -70.0430999999999955, 'S 30 23 44', 'O 70 02 35', 177, 134);
INSERT INTO bdc.mux_grid VALUES ('177/135', '0106000020E61000000100000001030000000100000005000000FC1B0E210CAB51C06CBEC57353C03EC0D0BF7009B56F51C0B111E776D1E33EC04607F64D4A7F51C061CA7A8A7EC73FC072639365A1BA51C01C77598700A43FC0FC1B0E210CAB51C06CBEC57353C03EC0', 1229, 1229, 3901, -31.2852999999999994, -70.2857999999999947, 'S 31 17 06', 'O 70 17 08', 177, 135);
INSERT INTO bdc.mux_grid VALUES ('177/136', '0106000020E61000000100000001030000000100000005000000301EE8D5AABA51C0D85F1BE2FAA33FC0762F3B765C7F51C06D2F48AE73C73FC000879C102A8F51C00C78C596825540C0BA75497078CA51C04210AF30C64340C0301EE8D5AABA51C0D85F1BE2FAA33FC0', 1230, 1230, 3902, -32.1743000000000023, -70.531800000000004, 'S 32 10 27', 'O 70 31 54', 177, 136);
INSERT INTO bdc.mux_grid VALUES ('177/137', '0106000020E610000001000000010300000001000000050000004873C36382CA51C0F8B0D736C34340C0F616DE343D8F51C0EE7550DD7C5540C08253BB3C469F51C03AA12F4937C740C0D2AFA06B8BDA51C046DCB6A27DB540C04873C36382CA51C0F8B0D736C34340C0', 1231, 1231, 3903, -33.0628999999999991, -70.781400000000005, 'S 33 03 46', 'O 70 46 53', 177, 137);
INSERT INTO bdc.mux_grid VALUES ('177/138', '0106000020E610000001000000010300000001000000050000008ED49FE995DA51C0E092727F7AB540C0F82E226B5A9F51C0CEDD224031C740C0D0A69F25A2AF51C0C0694DC9DC3841C0644C1DA4DDEA51C0D21E9D08262741C08ED49FE995DA51C0E092727F7AB540C0', 1232, 1232, 3904, -33.9510000000000005, -71.0348000000000042, 'S 33 57 03', 'O 71 02 05', 177, 138);
INSERT INTO bdc.mux_grid VALUES ('177/139', '0106000020E61000000100000001030000000100000005000000A8A299B4E8EA51C08CD489B9222741C05035776DB7AF51C0EEF6156CD63841C0BCBDF15041C051C0A6B4B67D72AA41C0142B149872FB51C044922ACBBE9841C0A8A299B4E8EA51C08CD489B9222741C0', 1233, 1233, 3906, -34.8387000000000029, -71.292199999999994, 'S 34 50 19', 'O 71 17 31', 177, 139);
INSERT INTO bdc.mux_grid VALUES ('177/140', '0106000020E61000000100000001030000000100000005000000FAE4AB437EFB51C0BE7FB44DBB9841C0CC73C2C257C051C05AD362C76BAA41C05ADEDB7A27D151C0B2D829C6F71B42C0884FC5FB4D0C52C016857B4C470A42C0FAE4AB437EFB51C0BE7FB44DBB9841C0', 1234, 1234, 3907, -35.7257999999999996, -71.5537999999999954, 'S 35 43 33', 'O 71 33 13', 177, 140);
INSERT INTO bdc.mux_grid VALUES ('177/141', '0106000020E610000001000000010300000001000000050000001452CC4B5A0C52C0528CD89D430A42C030B088283FD151C0622A60B1F01B42C01CB6969A58E251C02479DBFA6B8D42C00058DABD731D52C014DB53E7BE7B42C01452CC4B5A0C52C0528CD89D430A42C0', 1235, 1235, 3908, -36.6124999999999972, -71.8198000000000008, 'S 36 36 45', 'O 71 49 11', 177, 141);
INSERT INTO bdc.mux_grid VALUES ('177/142', '0106000020E6100000010000000103000000010000000500000014876BBC801D52C0425B7E04BB7B42C022CD7D9771E251C0A237D181648D42C0CD9766E7D8F351C03F39B46BCEFE42C0BE51540CE82E52C0E05C61EE24ED42C014876BBC801D52C0425B7E04BB7B42C0', 1236, 1236, 3909, -37.4986000000000033, -72.0905000000000058, 'S 37 29 55', 'O 72 05 25', 177, 142);
INSERT INTO bdc.mux_grid VALUES ('177/143', '0106000020E610000001000000010300000001000000050000007CD564C4F52E52C0F46E12D420ED42C0F6B78548F3F351C046542288C6FE42C090AB16DEAC0552C0C83B7A5F1E7043C016C9F559AF4052C074566AAB785E43C07CD564C4F52E52C0F46E12D420ED42C0', 1237, 1237, 3910, -38.3841999999999999, -72.3662000000000063, 'S 38 23 03', 'O 72 21 58', 177, 143);
INSERT INTO bdc.mux_grid VALUES ('177/144', '0106000020E6100000010000000103000000010000000500000080856AD7BD4052C0B8611356745E43C0DCBA33BAC80552C0343A910A167043C026CF0047D91752C0A00AE4125BE143C0CA993764CE5252C02632665EB9CF43C080856AD7BD4052C0B8611356745E43C0', 1238, 1238, 3912, -39.2691999999999979, -72.6470999999999947, 'S 39 16 09', 'O 72 38 49', 177, 144);
INSERT INTO bdc.mux_grid VALUES ('177/91', '0106000020E61000000100000001030000000100000005000000D33FCB59F2C64EC05D29B4B7DC332140018809705F4F4EC0B2FD21E357EC2040E1BF10C1CB684EC0C8304C588B431E40B277D2AA5EE04EC01988700195D21E40D33FCB59F2C64EC05D29B4B7DC332140', 1239, 1239, 3948, 8.06359999999999921, -61.1415000000000006, 'N 08 03 49', 'O 61 08 29', 177, 91);
INSERT INTO bdc.mux_grid VALUES ('177/92', '0106000020E61000000100000001030000000100000005000000749CD8445BE04EC067C4BFF090D21E40BA5A3867C5684EC0F3156ABF83431E40110954D71E824EC08933A3BE46AE1A40CA4AF4B4B4F94EC0FDE1F8EF533D1B40749CD8445BE04EC067C4BFF090D21E40', 1240, 1240, 3949, 7.16790000000000038, -61.3397000000000006, 'N 07 10 04', 'O 61 20 22', 177, 92);
INSERT INTO bdc.mux_grid VALUES ('177/93', '0106000020E61000000100000001030000000100000005000000689E94B2B1F94EC07FC86D56503D1B4076A2E73A19824EC0D39F580840AE1A407C81E308629B4EC098A9994BED1817406E7D9080FA124FC044D2AE99FDA71740689E94B2B1F94EC07FC86D56503D1B40', 1241, 1241, 3952, 6.27210000000000001, -61.5373000000000019, 'N 06 16 19', 'O 61 32 14', 177, 93);
INSERT INTO bdc.mux_grid VALUES ('177/94', '0106000020E610000001000000010300000001000000050000006B8254E0F7124FC027698975FAA71740C4C628275D9B4EC06242A374E71817404D5C848997B44EC06F89A4D081831340F717B042322C4FC034B08AD1941214406B8254E0F7124FC027698975FAA71740', 1242, 1242, 3953, 5.37619999999999987, -61.734499999999997, 'N 05 22 34', 'O 61 44 04', 177, 94);
INSERT INTO bdc.mux_grid VALUES ('177/95', '0106000020E61000000100000001030000000100000005000000A5C65203302C4FC0042846219212144067E51E6093B44EC0814C2FD67C8313407CA43186C1CD4EC0E2E5AA3B0EDC0F40B98565295E454FC0744EEC681C7D1040A5C65203302C4FC00428462192121440', 1243, 1243, 3954, 4.48029999999999973, -61.9313000000000002, 'N 04 28 49', 'O 61 55 52', 177, 95);
INSERT INTO bdc.mux_grid VALUES ('177/96', '0106000020E6100000010000000103000000010000000500000016F9D1495C454FC07E6C3D2B1A7D10409A802013BECD4EC04D90F7FA05DC0F40806A3626E2E64EC05E993A0400B10840FBE2E75C805E4FC00DE2BD5F2ECF094016F9D1495C454FC07E6C3D2B1A7D1040', 1244, 1244, 3955, 3.58429999999999982, -62.1278000000000006, 'N 03 35 03', 'O 62 07 40', 177, 96);
INSERT INTO bdc.mux_grid VALUES ('177/97', '0106000020E610000001000000010300000001000000050000002E3838DC7E5E4FC0776C65C72ACF0940040FD267DFE64EC0E219C973F9B008405D07428CFBFF4EC09E641597DE8501408930A8009B774FC033B7B1EA0FA402402E3838DC7E5E4FC0776C65C72ACF0940', 1245, 1245, 3956, 2.68829999999999991, -62.3241000000000014, 'N 02 41 17', 'O 62 19 26', 177, 97);
INSERT INTO bdc.mux_grid VALUES ('177/98', '0106000020E61000000100000001030000000100000005000000DE9924DE99774FC0DDD1A6330DA402401B9D3A81F9FF4EC0483FC2B3D9850140019A77D70F194FC02E12141E5FB5F43FC4966134B0904FC05937DD1DC6F1F63FDE9924DE99774FC0DDD1A6330DA40240', 1246, 1246, 3958, 1.79220000000000002, -62.5200999999999993, 'N 01 47 31', 'O 62 31 12', 177, 98);
INSERT INTO bdc.mux_grid VALUES ('177/99', '0106000020E61000000100000001030000000100000005000000059E7F6FAF904FC01C06CC6FC2F1F63F09A6D37E0E194FC0DFBD00AD58B5F43F21DB792421324FC0EA3A4E30C47BD93F1BD32515C2A94FC0EFADBD9DB536E13F059E7F6FAF904FC01C06CC6FC2F1F63F', 1247, 1247, 3959, 0.896100000000000008, -62.7160000000000011, 'N 00 53 45', 'O 62 42 57', 177, 99);
INSERT INTO bdc.mux_grid VALUES ('178/100', '0106000020E61000000100000001030000000100000005000000C29996D0A51250C0C50D24BEB136E13FE6A73A71AAAD4FC0B9AC07B6B77BD93F51C51982BBC64FC0AE59525307DEDFBF762806592E1F50C0DBEA118D5BECD6BFC29996D0A51250C0C50D24BEB136E13F', 1248, 1248, 3960, 0, -63.8770000000000024, 'N 00 00 00', 'O 63 52 37', 178, 100);
INSERT INTO bdc.mux_grid VALUES ('178/101', '0106000020E61000000100000001030000000100000005000000607CC0532E1F50C0E775E2565CECD6BF7D1DA58CBBC64FC090CE818906DEDFBFA7B5C823CDDF4FC0DCFDAB51EE4DF6BF7648521FB72B50C0B22704C58311F4BF607CC0532E1F50C0E775E2565CECD6BF', 1249, 1249, 3963, -0.896100000000000008, -64.0728000000000009, 'S 00 53 45', 'O 64 04 22', 178, 101);
INSERT INTO bdc.mux_grid VALUES ('178/102', '0106000020E61000000100000001030000000100000005000000926E9348B72B50C0F3BC373A8211F4BF3201C9DFCDDF4FC076261ACEEA4DF6BFDA258018E2F84FC0F85A579B245202C0E200EF64413850C044266651F03301C0926E9348B72B50C0F3BC373A8211F4BF', 1250, 1250, 3964, -1.79220000000000002, -64.2686999999999955, 'S 01 47 31', 'O 64 16 07', 178, 102);
INSERT INTO bdc.mux_grid VALUES ('178/103', '0106000020E61000000100000001030000000100000005000000488DCABC413850C0B3FB01ADEE3301C0DBD04E86E3F84FC0A0A42930215202C0F2FA993EFE0850C06FF73AA7437D09C0CE1F3D38CE4450C0834E1324115F08C0488DCABC413850C0B3FB01ADEE3301C0', 1251, 1251, 3965, -2.68829999999999991, -64.4647999999999968, 'S 02 41 17', 'O 64 27 53', 178, 103);
INSERT INTO bdc.mux_grid VALUES ('178/104', '0106000020E6100000010000000103000000010000000500000024D4DCBECE4450C0B461E99F0E5F08C07499BF4EFF0850C0E2B307913E7D09C03CB3C0388F1550C0D4F04658275410C0EEEDDDA85E5150C0708F6FBF1E8A0FC024D4DCBECE4450C0B461E99F0E5F08C0', 1252, 1252, 3966, -3.58429999999999982, -64.6610000000000014, 'S 03 35 03', 'O 64 39 39', 178, 104);
INSERT INTO bdc.mux_grid VALUES ('178/105', '0106000020E6100000010000000103000000010000000500000040E4815E5F5150C0A6274D5A1B8A0FC01470A6A2901550C082E973F6235410C092B45D0C252250C060BDD50CA0E913C0BE2839C8F35D50C0B36788C3895A13C040E4815E5F5150C0A6274D5A1B8A0FC0', 1253, 1253, 3968, -4.48029999999999973, -64.8575000000000017, 'S 04 28 49', 'O 64 51 26', 178, 105);
INSERT INTO bdc.mux_grid VALUES ('178/106', '0106000020E61000000100000001030000000100000005000000901538ADF45D50C01A86AB9F875A13C08EA5B0D0262250C02F37ABD29BE913C046627DCDC02E50C0D3E66221097F17C048D204AA8E6A50C0BE3563EEF4EF16C0901538ADF45D50C01A86AB9F875A13C0', 1254, 1254, 3969, -5.37619999999999987, -65.0542999999999978, 'S 05 22 34', 'O 65 03 15', 178, 106);
INSERT INTO bdc.mux_grid VALUES ('178/107', '0106000020E61000000100000001030000000100000005000000C65DCCBE8F6A50C0ED4C3458F2EF16C0D08E16EDC22E50C034A6D90C047F17C00C951993633B50C07F5CB3C45F141BC00464CF64307750C037030E104E851AC0C65DCCBE8F6A50C0ED4C3458F2EF16C0', 1255, 1255, 3970, -6.27210000000000001, -65.251499999999993, 'S 06 16 19', 'O 65 15 05', 178, 107);
INSERT INTO bdc.mux_grid VALUES ('178/108', '0106000020E61000000100000001030000000100000005000000A69BE4A9317750C09BC04E064B851AC018D5FE0E663B50C051EE58D359141BC0D631A7770E4850C02628F423A1A91EC064F88C12DA8350C071FAE956921A1EC0A69BE4A9317750C09BC04E064B851AC0', 1256, 1256, 3971, -7.16790000000000038, -65.4491000000000014, 'S 07 10 04', 'O 65 26 56', 178, 108);
INSERT INTO bdc.mux_grid VALUES ('178/109', '0106000020E6100000010000000103000000010000000500000020D98C88DB8350C095C722D88E1A1EC0763C0C51114850C0595AE8529AA91EC09865A799C25450C017B23835651F21C0420228D18C9050C0B4E8D577DFD720C020D98C88DB8350C095C722D88E1A1EC0', 1257, 1257, 3974, -8.06359999999999921, -65.6473000000000013, 'S 08 03 49', 'O 65 38 50', 178, 109);
INSERT INTO bdc.mux_grid VALUES ('178/110', '0106000020E61000000100000001030000000100000005000000E41CC8788E9050C08125157DDDD720C06810EFD1C55450C0D3A4315B611F21C04E243D1C816150C08C8DA360ECE922C0CA3016C3499D50C0390E878268A222C0E41CC8788E9050C08125157DDDD720C0', 1258, 1258, 3975, -8.95919999999999916, -65.846100000000007, 'S 08 57 33', 'O 65 50 45', 178, 110);
INSERT INTO bdc.mux_grid VALUES ('178/111', '0106000020E61000000100000001030000000100000005000000E068259D4B9D50C0B0A4714B66A222C0B2D6FAB4846150C0ADC93813E8E922C0D692C7274B6E50C0888D85A764B424C00425F20F12AA50C08B68BEDFE26C24C0E068259D4B9D50C0B0A4714B66A222C0', 1259, 1259, 3976, -9.85479999999999912, -66.0455000000000041, 'S 09 51 17', 'O 66 02 43', 178, 111);
INSERT INTO bdc.mux_grid VALUES ('178/112', '0106000020E61000000100000001030000000100000005000000588C591D14AA50C0BC8A3D6BE06C24C096EEC0224F6E50C03B6D98E45FB424C0420A82EA217B50C0F672B79BCC7E26C004A81AE5E6B650C077905C224D3726C0588C591D14AA50C0BC8A3D6BE06C24C0', 1260, 1260, 3977, -10.7501999999999995, -66.2456999999999994, 'S 10 45 00', 'O 66 14 44', 178, 112);
INSERT INTO bdc.mux_grid VALUES ('178/113', '0106000020E610000001000000010300000001000000050000000078DE26E9B650C0B7F4386F4A3726C0EBCDB049267B50C0D7F9EA60C77E26C0D46F2A99068850C0734D6CCD224928C0EC195876C9C350C05348BADBA50128C00078DE26E9B650C0B7F4386F4A3726C0', 1261, 1261, 3979, -11.6454000000000004, -66.446700000000007, 'S 11 38 43', 'O 66 26 48', 178, 113);
INSERT INTO bdc.mux_grid VALUES ('178/114', '0106000020E61000000100000001030000000100000005000000ECCB98EDCBC350C0DBD99AE8A20128C09494BE5E0B8850C040A022181D4928C0B2A5AE6FFA9450C096F4F8CA65132AC00CDD88FEBAD050C0312E719BEBCB29C0ECCB98EDCBC350C0DBD99AE8A20128C0', 1262, 1262, 3980, -12.5404999999999998, -66.6486000000000018, 'S 12 32 25', 'O 66 38 54', 178, 114);
INSERT INTO bdc.mux_grid VALUES ('178/115', '0106000020E610000001000000010300000001000000050000004A6584ACBDD050C08794D966E8CB29C004BE109EFF9450C0978350985F132AC09CE8E1B1FEA150C0CFF2952094DD2BC0E28F55C0BCDD50C0BE031FEF1C962BC04A6584ACBDD050C08794D966E8CB29C0', 1263, 1263, 3981, -13.4354999999999993, -66.8513999999999982, 'S 13 26 07', 'O 66 51 04', 178, 115);
INSERT INTO bdc.mux_grid VALUES ('178/116', '0106000020E61000000100000001030000000100000005000000B0BB68A6BFDD50C09BFF6D7719962BC02AC3B54B04A250C06A52666D8DDD2BC096FB3AAC14AF50C0D1471B58ACA72DC01CF4ED06D0EA50C003F5226238602DC0B0BB68A6BFDD50C09BFF6D7719962BC0', 1264, 1264, 3982, -14.3302999999999994, -67.0551999999999992, 'S 14 19 49', 'O 67 03 18', 178, 116);
INSERT INTO bdc.mux_grid VALUES ('178/117', '0106000020E6100000010000000103000000010000000500000084EE9526D3EA50C0848F90A534602DC0A88F62B41AAF50C050B1F120A5A72DC0C4149CB43DBC50C09763B5F8AC712FC0A073CF26F6F750C0CB41547D3C2A2FC084EE9526D3EA50C0848F90A534602DC0', 1265, 1265, 3984, -15.2249999999999996, -67.2601999999999975, 'S 15 13 29', 'O 67 15 36', 178, 117);
INSERT INTO bdc.mux_grid VALUES ('178/118', '0106000020E61000000100000001030000000100000005000000FE73AB81F9F750C063C9EF79382A2FC002BE3A2E44BC50C0F2D6D039A5712FC09691252B7BC950C0B5534943CA9D30C09247967E300551C0EECC58E3137A30C0FE73AB81F9F750C063C9EF79382A2FC0', 1266, 1266, 3986, -16.1193999999999988, -67.466399999999993, 'S 16 07 09', 'O 67 27 58', 178, 118);
INSERT INTO bdc.mux_grid VALUES ('178/119', '0106000020E61000000100000001030000000100000005000000186C6916340551C04CB52FBD117A30C06AA0A31982C950C0EED3EF1DC69D30C0C48C147BCED650C09A6044C1B08231C07258DA77801251C0F7418460FC5E31C0186C6916340551C04CB52FBD117A30C0', 1267, 1267, 3987, -17.0137, -67.6738, 'S 17 00 49', 'O 67 40 25', 178, 119);
INSERT INTO bdc.mux_grid VALUES ('178/120', '0106000020E610000001000000010300000001000000050000004EB18D4E841251C0DBCABF14FA5E31C08E3323E2D5D650C06151CE53AC8231C0E889AE1B39E450C0D77ED834896732C0AA071988E71F51C051F8C9F5D64332C04EB18D4E841251C0DBCABF14FA5E31C0', 1268, 1268, 3988, -17.9076999999999984, -67.8826999999999998, 'S 17 54 27', 'O 67 52 57', 178, 120);
INSERT INTO bdc.mux_grid VALUES ('178/121', '0106000020E610000001000000010300000001000000050000004CD7BD9FEB1F51C0F0922D83D44332C0002E4CFF40E450C0AC5DE27C846732C0AE843B91BCF150C0F76B7DDA524C33C0FA2DAD31672D51C03BA1C8E0A22833C04CD7BD9FEB1F51C0F0922D83D44332C0', 1269, 1269, 3990, -18.8016000000000005, -68.0929000000000002, 'S 18 48 05', 'O 68 05 34', 178, 121);
INSERT INTO bdc.mux_grid VALUES ('178/122', '0106000020E610000001000000010300000001000000050000001A617F8C6B2D51C0073AFE45A02833C0827BB8F5C4F150C040B472D54D4C33C03CCE0F6E5AFF50C0E3DE59EC0C3134C0D5B3D604013B51C0A864E55C5F0D34C01A617F8C6B2D51C0073AFE45A02833C0', 1270, 1270, 3991, -19.6951000000000001, -68.3048000000000002, 'S 19 41 42', 'O 68 18 17', 178, 122);
INSERT INTO bdc.mux_grid VALUES ('178/123', '0106000020E6100000010000000103000000010000000500000028983FA5053B51C0C3C37B985C0D34C0EC91135863FF50C0DAEC7197073134C0AA48A753140D51C0648E01A2B61535C0E84ED3A0B64851C04C650BA30BF234C028983FA5053B51C0C3C37B985C0D34C0', 1271, 1271, 3992, -20.5884999999999998, -68.5182999999999964, 'S 20 35 18', 'O 68 31 05', 178, 123);
INSERT INTO bdc.mux_grid VALUES ('178/124', '0106000020E61000000100000001030000000100000005000000B08E6C89BB4851C0E16574B308F234C05C2D36C81D0D51C01D353CFAB01535C06CB1D3F3EB1A51C08ECB2C304FFA35C0C0120AB5895651C052FC64E9A6D635C0B08E6C89BB4851C0E16574B308F234C0', 1272, 1272, 3993, -21.4816000000000003, -68.7335000000000065, 'S 21 28 53', 'O 68 44 00', 178, 124);
INSERT INTO bdc.mux_grid VALUES ('178/125', '0106000020E61000000100000001030000000100000005000000E0F7A0E88E5651C01399F3CCA3D635C07A2755F8F51A51C095964E3249FA35C0B2D7FF11E32851C0FD1769C8D5DE36C01AA84B027C6451C07C1A0E6330BB36C0E0F7A0E88E5651C01399F3CCA3D635C0', 1273, 1273, 3995, -22.3744000000000014, -68.9506999999999977, 'S 22 22 27', 'O 68 57 02', 178, 125);
INSERT INTO bdc.mux_grid VALUES ('178/126', '0106000020E61000000100000001030000000100000005000000B6B4E483816451C00147F4172DBB36C0E24945ACED2851C0CA2FF770CFDE36C0BACC8984FB3651C07811C29849C337C08E37295C8F7251C0AD28BF3FA79F37C0B6B4E483816451C00147F4172DBB36C0', 1274, 1274, 3997, -23.2669999999999995, -69.1697999999999951, 'S 23 16 01', 'O 69 10 11', 178, 126);
INSERT INTO bdc.mux_grid VALUES ('178/127', '0106000020E610000001000000010300000001000000050000001A14042F957251C0B9770BC4A39F37C02A28D6BA063751C049BAFDE342C337C0EA4C3636374551C0AEF961CBA9A738C0DC3864AAC58051C01EB76FAB0A8438C01A14042F957251C0B9770BC4A39F37C0', 1275, 1275, 3998, -24.1593000000000018, -69.390900000000002, 'S 24 09 33', 'O 69 23 27', 178, 127);
INSERT INTO bdc.mux_grid VALUES ('178/128', '0106000020E61000000100000001030000000100000005000000FC0600D2CB8051C096C40AFD068438C04244460F434551C06FA243B5A2A738C0DCDEBF27985351C049132986F58B39C094A179EA208F51C07135F0CD596839C0FC0600D2CB8051C096C40AFD068438C0', 1276, 1276, 4000, -25.0512000000000015, -69.6143000000000001, 'S 25 03 04', 'O 69 36 51', 178, 128);
INSERT INTO bdc.mux_grid VALUES ('178/129', '0106000020E61000000100000001030000000100000005000000C8BB996A278F51C03ECF99EA556839C0FAFBD2AAA45351C0EAE85A0AEE8B39C028668471206251C0CBEF3AEA2B703AC0F6254B31A39D51C020D679CA934C3AC0C8BB996A278F51C03ECF99EA556839C0', 1277, 1277, 4001, -25.9429000000000016, -69.8400000000000034, 'S 25 56 34', 'O 69 50 24', 178, 129);
INSERT INTO bdc.mux_grid VALUES ('178/130', '0106000020E610000001000000010300000001000000050000004255FC0DAA9D51C07DDEC5AF8F4C3AC030FE66A62D6251C03AE9120424703AC03E325445D27051C097BE80134C543BC05089E9AC4EAC51C0DCB333BFB7303BC04255FC0DAA9D51C07DDEC5AF8F4C3AC0', 1278, 1278, 4002, -26.8341999999999992, -70.0682000000000045, 'S 26 50 03', 'O 70 04 05', 178, 130);
INSERT INTO bdc.mux_grid VALUES ('178/131', '0106000020E6100000010000000103000000010000000500000018C287EA55AC51C0D4B2866AB3303BC0F4576A34E07051C0A010FABD43543BC01DEA65F0AF7F51C095891F1855383CC0405483A625BB51C0C92BACC4C4143CC018C287EA55AC51C0D4B2866AB3303BC0', 1279, 1279, 4003, -27.7251000000000012, -70.2989000000000033, 'S 27 43 30', 'O 70 17 56', 178, 131);
INSERT INTO bdc.mux_grid VALUES ('178/132', '0106000020E610000001000000010300000001000000050000003803C0492DBB51C0708A3733C0143CC0E073B7A2BE7F51C0E275D34D4C383CC0340A73DDBB8E51C0462BE107461C3DC08C997B842ACA51C0D33F45EDB9F83CC03803C0492DBB51C0708A3733C0143CC0', 1280, 1280, 4005, -28.6157000000000004, -70.5323999999999955, 'S 28 36 56', 'O 70 31 56', 178, 132);
INSERT INTO bdc.mux_grid VALUES ('178/133', '0106000020E61000000100000001030000000100000005000000D896649232CA51C03820031CB5F83CC0DACDB85CCB8E51C01E16FFC23C1C3DC0CC1F0197F89D51C07CBA8EEB1D003EC0CAE8ACCC5FD951C097C4924496DC3DC0D896649232CA51C03820031CB5F83CC0', 1281, 1281, 4006, -29.5060000000000002, -70.7687999999999988, 'S 29 30 21', 'O 70 46 07', 178, 133);
INSERT INTO bdc.mux_grid VALUES ('178/134', '0106000020E61000000100000001030000000100000005000000B61DB44A68D951C0C86E413091DC3DC0EA85B3ED089E51C0EB72D32514003EC0525FDCC968AD51C006ED3AC4DBE33EC01CF7DC26C8E851C0E3E8A8CE58C03EC0B61DB44A68D951C0C86E413091DC3DC0', 1282, 1282, 4007, -30.3958000000000013, -71.0083000000000055, 'S 30 23 44', 'O 71 00 29', 178, 134);
INSERT INTO bdc.mux_grid VALUES ('178/90', '0106000020E61000000100000001030000000100000005000000099C769EFE284FC0DAA58E7D63FE2240A1D6D6036FB14EC0E423ABA3E0B622409C690E7EF0CA4EC0145CBA225CEC2040022FAE1880424FC00ADE9DFCDE332140099C769EFE284FC0DAA58E7D63FE2240', 1283, 1283, 4059, 8.95919999999999916, -61.9078999999999979, 'N 08 57 33', 'O 61 54 28', 178, 90);
INSERT INTO bdc.mux_grid VALUES ('178/91', '0106000020E610000001000000010300000001000000050000006EA7704D7C424FC02929B4B7DC332140BFEFAE63E9CA4EC093FD21E357EC20409A27B6B455E44EC006314C588B431E4049DF779EE85B4FC02F88700195D21E406EA7704D7C424FC02929B4B7DC332140', 1284, 1284, 4060, 8.06359999999999921, -62.1066000000000003, 'N 08 03 49', 'O 62 06 23', 178, 91);
INSERT INTO bdc.mux_grid VALUES ('178/92', '0106000020E6100000010000000103000000010000000500000023047E38E55B4FC096C4BFF090D21E4057C2DD5A4FE44EC00E166ABF83431E40B070F9CAA8FD4EC02533A3BE46AE1A407CB299A83E754FC0ACE1F8EF533D1B4023047E38E55B4FC096C4BFF090D21E40', 1285, 1285, 4061, 7.16790000000000038, -62.3048000000000002, 'N 07 10 04', 'O 62 18 17', 178, 92);
INSERT INTO bdc.mux_grid VALUES ('178/93', '0106000020E610000001000000010300000001000000050000001E063AA63B754FC031C86D56503D1B40080A8D2EA3FD4EC05C9F580840AE1A400BE988FCEB164FC0A3A9994BED18174021E53574848E4FC078D2AE99FDA717401E063AA63B754FC031C86D56503D1B40', 1286, 1286, 4064, 6.27210000000000001, -62.5024999999999977, 'N 06 16 19', 'O 62 30 08', 178, 93);
INSERT INTO bdc.mux_grid VALUES ('178/94', '0106000020E6100000010000000103000000010000000500000006EAF9D3818E4FC040698975FAA71740712ECE1AE7164FC08F42A374E7181740F5C3297D21304FC01E8AA4D0818313408C7F5536BCA74FC0CFB08AD19412144006EAF9D3818E4FC040698975FAA71740', 1287, 1287, 4065, 5.37619999999999987, -62.6997, 'N 05 22 34', 'O 62 41 58', 178, 94);
INSERT INTO bdc.mux_grid VALUES ('178/95', '0106000020E61000000100000001030000000100000005000000452EF8F6B9A74FC0AA28462192121440064DC4531D304FC0294D2FD67C8313401F0CD7794B494FC02EE6AA3B0EDC0F405DED0A1DE8C04FC0984EEC681C7D1040452EF8F6B9A74FC0AA28462192121440', 1288, 1288, 4066, 4.48029999999999973, -62.8965000000000032, 'N 04 28 49', 'O 62 53 47', 178, 95);
INSERT INTO bdc.mux_grid VALUES ('178/96', '0106000020E61000000100000001030000000100000005000000B360773DE6C04FC09C6C3D2B1A7D104041E8C50648494FC09A90F7FA05DC0F4026D2DB196C624FC0AA993A0400B10840974A8D500ADA4FC047E2BD5F2ECF0940B360773DE6C04FC09C6C3D2B1A7D1040', 1289, 1289, 4067, 3.58429999999999982, -63.0930000000000035, 'N 03 35 03', 'O 63 05 34', 178, 96);
INSERT INTO bdc.mux_grid VALUES ('178/97', '0106000020E61000000100000001030000000100000005000000E09FDDCF08DA4FC0E06C65C72ACF09409976775B69624FC0111AC973F9B00840F56EE77F857B4FC0CD641597DE8501403B984DF424F34FC09CB7B1EA0FA40240E09FDDCF08DA4FC0E06C65C72ACF0940', 1290, 1290, 4069, 2.68829999999999991, -63.289200000000001, 'N 02 41 17', 'O 63 17 21', 178, 97);
INSERT INTO bdc.mux_grid VALUES ('178/98', '0106000020E610000001000000010300000001000000050000007E01CAD123F34FC020D2A6330DA40240BD04E074837B4FC08D3FC2B3D9850140A3011DCB99944FC07112141E5FB5F43F347F03141D0650C09F37DD1DC6F1F63F7E01CAD123F34FC020D2A6330DA40240', 1291, 1291, 4070, 1.79220000000000002, -63.485199999999999, 'N 01 47 31', 'O 63 29 06', 178, 98);
INSERT INTO bdc.mux_grid VALUES ('178/99', '0106000020E61000000100000001030000000100000005000000D28292B11C0650C05806CC6FC2F1F63FA90D797298944FC019BE00AD58B5F43FC3421F18ABAD4FC0863A4E30C47BD93F629D6504A61250C0F6ADBD9DB536E13FD28292B11C0650C05806CC6FC2F1F63F', 1292, 1292, 4071, 0.896100000000000008, -63.6811000000000007, 'N 00 53 45', 'O 63 40 52', 178, 99);
INSERT INTO bdc.mux_grid VALUES ('179/100', '0106000020E61000000100000001030000000100000005000000944D69CA6A5050C0040E24BEB136E13FC40770329A1450C027AD07B6B77BD93F7A96DFBA222150C02F59525307DEDFBF48DCD852F35C50C04CEA118D5BECD6BF944D69CA6A5050C0040E24BEB136E13F', 1293, 1293, 4072, 0, -64.8421000000000021, 'N 00 00 00', 'O 64 50 31', 179, 100);
INSERT INTO bdc.mux_grid VALUES ('179/101', '0106000020E610000001000000010300000001000000050000003230934DF35C50C05875E2565CECD6BF904225C0222150C0FACD818906DEDFBFA40EB78BAB2D50C0CBFDAB51EE4DF6BF48FC24197C6950C0A22704C58311F4BF3230934DF35C50C05875E2565CECD6BF', 1294, 1294, 4074, -0.896100000000000008, -65.0379999999999967, 'S 00 53 45', 'O 65 02 16', 179, 101);
INSERT INTO bdc.mux_grid VALUES ('179/102', '0106000020E61000000100000001030000000100000005000000642266427C6950C0DABC373A8211F4BF6C34B7E9AB2D50C052261ACEEA4DF6BFBCC61206363A50C0FB5A579B245202C0B4B4C15E067650C044266651F03301C0642266427C6950C0DABC373A8211F4BF', 1295, 1295, 4075, -1.79220000000000002, -65.2339000000000055, 'S 01 47 31', 'O 65 14 01', 179, 102);
INSERT INTO bdc.mux_grid VALUES ('179/103', '0106000020E610000001000000010300000001000000050000001A419DB6067650C0BBFB01ADEE3301C03A1CFABC363A50C0BAA42930215202C0C0AE6C38C34650C090F73AA7437D09C0A0D30F32938250C0914E1324115F08C01A419DB6067650C0BBFB01ADEE3301C0', 1296, 1296, 4076, -2.68829999999999991, -65.4299000000000035, 'S 02 41 17', 'O 65 25 47', 179, 103);
INSERT INTO bdc.mux_grid VALUES ('179/104', '0106000020E61000000100000001030000000100000005000000F487AFB8938250C0BF61E99F0E5F08C0464D9248C44650C0E1B307913E7D09C010679332545350C0D4F04658275410C0BEA1B0A2238F50C0868F6FBF1E8A0FC0F487AFB8938250C0BF61E99F0E5F08C0', 1297, 1297, 4078, -3.58429999999999982, -65.6260999999999939, 'S 03 35 03', 'O 65 37 34', 179, 104);
INSERT INTO bdc.mux_grid VALUES ('179/105', '0106000020E6100000010000000103000000010000000500000014985458248F50C0B6274D5A1B8A0FC0E623799C555350C088E973F6235410C062683006EA5F50C0EBBCD50CA0E913C090DC0BC2B89B50C03E6788C3895A13C014985458248F50C0B6274D5A1B8A0FC0', 1298, 1298, 4079, -4.48029999999999973, -65.8225999999999942, 'S 04 28 49', 'O 65 49 21', 179, 105);
INSERT INTO bdc.mux_grid VALUES ('179/106', '0106000020E610000001000000010300000001000000050000006AC90AA7B99B50C08F85AB9F875A13C0605983CAEB5F50C0B936ABD29BE913C01A1650C7856C50C022E76221097F17C02686D7A353A850C0F93563EEF4EF16C06AC90AA7B99B50C08F85AB9F875A13C0', 1299, 1299, 4080, -5.37619999999999987, -66.0194000000000045, 'S 05 22 34', 'O 66 01 09', 179, 106);
INSERT INTO bdc.mux_grid VALUES ('179/107', '0106000020E610000001000000010300000001000000050000009E119FB854A850C03B4D3458F2EF16C09C42E9E6876C50C096A6D90C047F17C0D848EC8C287950C0A55CB3C45F141BC0DA17A25EF5B450C04A030E104E851AC09E119FB854A850C03B4D3458F2EF16C0', 1300, 1300, 4081, -6.27210000000000001, -66.2165999999999997, 'S 06 16 19', 'O 66 12 59', 179, 107);
INSERT INTO bdc.mux_grid VALUES ('179/108', '0106000020E61000000100000001030000000100000005000000764FB7A3F6B450C0B8C04E064B851AC0E888D1082B7950C06EEE58D359141BC0A8E57971D38550C08928F423A1A91EC036AC5F0C9FC150C0D2FAE956921A1EC0764FB7A3F6B450C0B8C04E064B851AC0', 1301, 1301, 4083, -7.16790000000000038, -66.4142999999999972, 'S 07 10 04', 'O 66 24 51', 179, 108);
INSERT INTO bdc.mux_grid VALUES ('179/109', '0106000020E61000000100000001030000000100000005000000EC8C5F82A0C150C007C822D88E1A1EC043F0DE4AD68550C0CC5AE8529AA91EC066197A93879250C0B4B23835651F21C010B6FACA51CE50C053E9D577DFD720C0EC8C5F82A0C150C007C822D88E1A1EC0', 1302, 1302, 4085, -8.06359999999999921, -66.6124999999999972, 'S 08 03 49', 'O 66 36 44', 179, 109);
INSERT INTO bdc.mux_grid VALUES ('179/110', '0106000020E61000000100000001030000000100000005000000BAD09A7253CE50C01526157DDDD720C03EC4C1CB8A9250C067A5315B611F21C020D80F16469F50C0818DA360ECE922C09CE4E8BC0EDB50C02E0E878268A222C0BAD09A7253CE50C01526157DDDD720C0', 1303, 1303, 4086, -8.95919999999999916, -66.8111999999999995, 'S 08 57 33', 'O 66 48 40', 179, 110);
INSERT INTO bdc.mux_grid VALUES ('179/111', '0106000020E61000000100000001030000000100000005000000B81CF89610DB50C09FA4714B66A222C0788ACDAE499F50C0AFC93813E8E922C09E469A2110AC50C0EC8D85A764B424C0DED8C409D7E750C0DC68BEDFE26C24C0B81CF89610DB50C09FA4714B66A222C0', 1304, 1304, 4087, -9.85479999999999912, -67.0106999999999999, 'S 09 51 17', 'O 67 00 38', 179, 111);
INSERT INTO bdc.mux_grid VALUES ('179/112', '0106000020E610000001000000010300000001000000050000003E402C17D9E750C0008B3D6BE06C24C058A2931C14AC50C0A76D98E45FB424C004BE54E4E6B850C04573B79BCC7E26C0EA5BEDDEABF450C09D905C224D3726C03E402C17D9E750C0008B3D6BE06C24C0', 1305, 1305, 4089, -10.7501999999999995, -67.2108999999999952, 'S 10 45 00', 'O 67 12 39', 179, 112);
INSERT INTO bdc.mux_grid VALUES ('179/113', '0106000020E61000000100000001030000000100000005000000D22BB120AEF450C0F3F4386F4A3726C0BC818343EBB850C013FAEA60C77E26C0A423FD92CBC550C0934D6CCD224928C0BCCD2A708E0151C07148BADBA50128C0D22BB120AEF450C0F3F4386F4A3726C0', 1306, 1306, 4090, -11.6454000000000004, -67.4117999999999995, 'S 11 38 43', 'O 67 24 42', 179, 113);
INSERT INTO bdc.mux_grid VALUES ('179/114', '0106000020E61000000100000001030000000100000005000000C87F6BE7900151C0F0D99AE8A20128C06E489158D0C550C054A022181D4928C08C598169BFD250C08CF4F8CA65132AC0E6905BF87F0E51C0292E719BEBCB29C0C87F6BE7900151C0F0D99AE8A20128C0', 1307, 1307, 4091, -12.5404999999999998, -67.6136999999999944, 'S 12 32 25', 'O 67 36 49', 179, 114);
INSERT INTO bdc.mux_grid VALUES ('179/115', '0106000020E610000001000000010300000001000000050000001E1957A6820E51C08494D966E8CB29C0D871E397C4D250C0938350985F132AC06E9CB4ABC3DF50C0ADF2952094DD2BC0B44328BA811B51C09E031FEF1C962BC01E1957A6820E51C08494D966E8CB29C0', 1308, 1308, 4092, -13.4354999999999993, -67.8165000000000049, 'S 13 26 07', 'O 67 48 59', 179, 115);
INSERT INTO bdc.mux_grid VALUES ('179/116', '0106000020E61000000100000001030000000100000005000000806F3BA0841B51C07EFF6D7719962BC0FA768845C9DF50C04D52666D8DDD2BC068AF0DA6D9EC50C016481B58ACA72DC0EEA7C000952851C049F5226238602DC0806F3BA0841B51C07EFF6D7719962BC0', 1309, 1309, 4094, -14.3302999999999994, -68.0203999999999951, 'S 14 19 49', 'O 68 01 13', 179, 116);
INSERT INTO bdc.mux_grid VALUES ('179/117', '0106000020E6100000010000000103000000010000000500000076A26820982851C0A68F90A534602DC0764335AEDFEC50C09BB1F120A5A72DC090C86EAE02FA50C0C463B5F8AC712FC09027A220BB3551C0D141547D3C2A2FC076A26820982851C0A68F90A534602DC0', 1310, 1310, 4095, -15.2249999999999996, -68.2253000000000043, 'S 15 13 29', 'O 68 13 31', 179, 117);
INSERT INTO bdc.mux_grid VALUES ('179/118', '0106000020E61000000100000001030000000100000005000000CE277E7BBE3551C08EC9EF79382A2FC0D2710D2809FA50C01DD7D039A5712FC06C45F824400751C033544943CA9D30C068FB6878F54251C06BCD58E3137A30C0CE277E7BBE3551C08EC9EF79382A2FC0', 1311, 1311, 4097, -16.1193999999999988, -68.4314999999999998, 'S 16 07 09', 'O 68 25 53', 179, 118);
INSERT INTO bdc.mux_grid VALUES ('179/119', '0106000020E61000000100000001030000000100000005000000E61F3C10F94251C0CDB52FBD117A30C05C547613470751C05DD4EF1DC69D30C0B440E774931451C0FA6044C1B08231C0400CAD71455051C06B428460FC5E31C0E61F3C10F94251C0CDB52FBD117A30C0', 1312, 1312, 4098, -17.0137, -68.6389999999999958, 'S 17 00 49', 'O 68 38 20', 179, 119);
INSERT INTO bdc.mux_grid VALUES ('179/120', '0106000020E6100000010000000103000000010000000500000018656048495051C051CBBF14FA5E31C07AE7F5DB9A1451C0C551CE53AC8231C0D23D8115FE2151C02C7FD834896732C072BBEB81AC5D51C0B7F8C9F5D64332C018656048495051C051CBBF14FA5E31C0', 1313, 1313, 4100, -17.9076999999999984, -68.8478000000000065, 'S 17 54 27', 'O 68 50 52', 179, 120);
INSERT INTO bdc.mux_grid VALUES ('179/121', '0106000020E610000001000000010300000001000000050000003E8B9099B05D51C040932D83D44332C0CEE11EF9052251C0115EE27C846732C07C380E8B812F51C04D6C7DDA524C33C0EAE17F2B2C6B51C07AA1C8E0A22833C03E8B9099B05D51C040932D83D44332C0', 1314, 1314, 4101, -18.8016000000000005, -69.058099999999996, 'S 18 48 05', 'O 69 03 29', 179, 121);
INSERT INTO bdc.mux_grid VALUES ('179/122', '0106000020E61000000100000001030000000100000005000000F2145286306B51C0563AFE45A02833C0582F8BEF892F51C08FB472D54D4C33C00A82E2671F3D51C0A3DE59EC0C3134C0A267A9FEC57851C06864E55C5F0D34C0F2145286306B51C0563AFE45A02833C0', 1315, 1315, 4102, -19.6951000000000001, -69.2699000000000069, 'S 19 41 42', 'O 69 16 11', 179, 122);
INSERT INTO bdc.mux_grid VALUES ('179/123', '0106000020E610000001000000010300000001000000050000000E4C129FCA7851C075C37B985C0D34C0AE45E651283D51C0A3EC7197073134C06CFC794DD94A51C01D8E01A2B61535C0CC02A69A7B8651C0F1640BA30BF234C00E4C129FCA7851C075C37B985C0D34C0', 1316, 1316, 4103, -20.5884999999999998, -69.4834000000000032, 'S 20 35 18', 'O 69 29 00', 179, 123);
INSERT INTO bdc.mux_grid VALUES ('179/124', '0106000020E6100000010000000103000000010000000500000072423F83808651C0996574B308F234C040E108C2E24A51C0C0343CFAB01535C05065A6EDB05851C020CB2C304FFA35C080C6DCAE4E9451C0F9FB64E9A6D635C072423F83808651C0996574B308F234C0', 1317, 1317, 4105, -21.4816000000000003, -69.6987000000000023, 'S 21 28 53', 'O 69 41 55', 179, 124);
INSERT INTO bdc.mux_grid VALUES ('179/125', '0106000020E61000000100000001030000000100000005000000B8AB73E2539451C0AD98F3CCA3D635C02EDB27F2BA5851C045964E3249FA35C06E8BD20BA86651C0201869C8D5DE36C0F85B1EFC40A251C0881A0E6330BB36C0B8AB73E2539451C0AD98F3CCA3D635C0', 1318, 1318, 4106, -22.3744000000000014, -69.9158000000000044, 'S 22 22 27', 'O 69 54 56', 179, 125);
INSERT INTO bdc.mux_grid VALUES ('179/126', '0106000020E61000000100000001030000000100000005000000A068B77D46A251C00447F4172DBB36C0AAFD17A6B26651C0E42FF770CFDE36C07E805C7EC07451C08211C29849C337C074EBFB5554B051C0A228BF3FA79F37C0A068B77D46A251C00447F4172DBB36C0', 1319, 1319, 4108, -23.2669999999999995, -70.1349000000000018, 'S 23 16 01', 'O 70 08 05', 179, 126);
INSERT INTO bdc.mux_grid VALUES ('179/89', '0106000020E610000001000000010300000001000000050000005AAC1ECEF38A4FC0496D055DDBC824408E1E85DF67134FC0FAE75FB55A81244051EBE1D5002D4FC0D3358258E5B622401A797BC48CA44FC022BB270066FE22405AAC1ECEF38A4FC0496D055DDBC82440', 1320, 1320, 4162, 9.85479999999999912, -62.6736000000000004, 'N 09 51 17', 'O 62 40 24', 179, 89);
INSERT INTO bdc.mux_grid VALUES ('179/90', '0106000020E61000000100000001030000000100000005000000BD031C9288A44FC005A68E7D63FE2240323E7CF7F82C4FC0FB23ABA3E0B622402DD1B3717A464FC00E5CBA225CEC2040BA96530C0ABE4FC017DE9DFCDE332140BD031C9288A44FC005A68E7D63FE2240', 1321, 1321, 4163, 8.95919999999999916, -62.8729999999999976, 'N 08 57 33', 'O 62 52 22', 179, 90);
INSERT INTO bdc.mux_grid VALUES ('179/91', '0106000020E61000000100000001030000000100000005000000150F164106BE4FC02F29B4B7DC3321405657545773464FC091FD21E357EC2040358F5BA8DF5F4FC0AD304C588B431E40F7461D9272D74FC0EC87700195D21E40150F164106BE4FC02F29B4B7DC332140', 1322, 1322, 4164, 8.06359999999999921, -63.0718000000000032, 'N 08 03 49', 'O 63 04 18', 179, 91);
INSERT INTO bdc.mux_grid VALUES ('179/92', '0106000020E61000000100000001030000000100000005000000C16B232C6FD74FC040C4BFF090D21E40092A834ED95F4FC0CE156ABF83431E405ED89EBE32794FC03333A3BE46AE1A40181A3F9CC8F04FC0A5E1F8EF533D1B40C16B232C6FD74FC040C4BFF090D21E40', 1323, 1323, 4166, 7.16790000000000038, -63.2700000000000031, 'N 07 10 04', 'O 63 16 11', 179, 92);
INSERT INTO bdc.mux_grid VALUES ('179/93', '0106000020E61000000100000001030000000100000005000000C96DDF99C5F04FC03CC86D56503D1B40B67132222D794FC06D9F580840AE1A40BB502EF075924FC0DEA9994BED18174064A6ED33070550C0A8D2AE99FDA71740C96DDF99C5F04FC03CC86D56503D1B40', 1324, 1324, 4168, 6.27210000000000001, -63.4675999999999974, 'N 06 16 19', 'O 63 28 03', 179, 93);
INSERT INTO bdc.mux_grid VALUES ('179/94', '0106000020E61000000100000001030000000100000005000000D4A8CFE3050550C06C698975FAA717400B96730E71924FC0AF42A374E7181740932BCF70ABAB4FC0F889A4D0818313409A73FD14A31150C0BAB08AD194121440D4A8CFE3050550C06C698975FAA71740', 1325, 1325, 4169, 5.37619999999999987, -63.6647999999999996, 'N 05 22 34', 'O 63 39 53', 179, 94);
INSERT INTO bdc.mux_grid VALUES ('179/95', '0106000020E61000000100000001030000000100000005000000F0CA4EF5A11150C08928462192121440ABB46947A7AB4FC00E4D2FD67C831340C1737C6DD5C44FC0EFE6AA3B0EDC0F407A2A5808391E50C0F04EEC681C7D1040F0CA4EF5A11150C08928462192121440', 1326, 1326, 4170, 4.48029999999999973, -63.8616000000000028, 'N 04 28 49', 'O 63 51 41', 179, 95);
INSERT INTO bdc.mux_grid VALUES ('179/96', '0106000020E6100000010000000103000000010000000500000030648E18381E50C00C6D3D2B1A7D1040DC4F6BFAD1C44FC05191F7FA05DC0F40C439810DF6DD4FC0DA993A0400B1084022591922CA2A50C099E2BD5F2ECF094030648E18381E50C00C6D3D2B1A7D1040', 1327, 1327, 4172, 3.58429999999999982, -64.058099999999996, 'N 03 35 03', 'O 64 03 29', 179, 96);
INSERT INTO bdc.mux_grid VALUES ('179/97', '0106000020E61000000100000001030000000100000005000000BE83C161C92A50C00E6D65C72ACF09404CDE1C4FF3DD4FC0691AC973F9B00840A5D68C730FF74FC01C651597DE850140EA7FF973573750C0BDB7B1EA0FA40240BE83C161C92A50C00E6D65C72ACF0940', 1328, 1328, 4173, 2.68829999999999991, -64.254400000000004, 'N 02 41 17', 'O 64 15 15', 179, 97);
INSERT INTO bdc.mux_grid VALUES ('179/98', '0106000020E6100000010000000103000000010000000500000090B4B7E2563750C04CD2A6330DA402405F6C85680DF74FC0BD3FC2B3D9850140A43461DF110850C08C12141E5FB5F43F0433D60DE24350C0B337DD1DC6F1F63F90B4B7E2563750C04CD2A6330DA40240', 1329, 1329, 4174, 1.79220000000000002, -64.4504000000000019, 'N 01 47 31', 'O 64 27 01', 179, 98);
INSERT INTO bdc.mux_grid VALUES ('179/99', '0106000020E61000000100000001030000000100000005000000A43665ABE14350C06B06CC6FC2F1F63FA43A0F33110850C02ABE00AD58B5F43F3455E2859A1450C0203B4E30C47BD93F325138FE6A5050C023AEBD9DB536E13FA43665ABE14350C06B06CC6FC2F1F63F', 1330, 1330, 4175, 0.896100000000000008, -64.6462999999999965, 'N 00 53 45', 'O 64 38 46', 179, 99);
INSERT INTO bdc.mux_grid VALUES ('180/100', '0106000020E6100000010000000103000000010000000500000064013CC42F8E50C0600D24BEB136E13F98BB422C5F5250C044AC07B6B77BD93F4C4AB2B4E75E50C03D59525307DEDFBF1890AB4CB89A50C0C0EA118D5BECD6BF64013CC42F8E50C0600D24BEB136E13F', 1331, 1331, 4177, 0, -65.8072999999999979, 'N 00 00 00', 'O 65 48 26', 180, 100);
INSERT INTO bdc.mux_grid VALUES ('180/101', '0106000020E6100000010000000103000000010000000500000002E46547B89A50C0CB75E2565CECD6BF62F6F7B9E75E50C02ACE818906DEDFBF76C28985706B50C0B8FDAB51EE4DF6BF19B0F71241A750C0AA2704C58311F4BF02E46547B89A50C0CB75E2565CECD6BF', 1332, 1332, 4179, -0.896100000000000008, -66.0031000000000034, 'S 00 53 45', 'O 66 00 11', 180, 101);
INSERT INTO bdc.mux_grid VALUES ('180/102', '0106000020E6100000010000000103000000010000000500000036D6383C41A750C0D9BC373A8211F4BF3EE889E3706B50C048261ACEEA4DF6BF8E7AE5FFFA7750C0EA5A579B245202C086689458CBB350C032266651F03301C036D6383C41A750C0D9BC373A8211F4BF', 1333, 1333, 4180, -1.79220000000000002, -66.1989999999999981, 'S 01 47 31', 'O 66 11 56', 180, 102);
INSERT INTO bdc.mux_grid VALUES ('180/103', '0106000020E61000000100000001030000000100000005000000ECF46FB0CBB350C0A5FB01ADEE3301C00CD0CCB6FB7750C0A5A42930215202C090623F32888450C074F73AA7437D09C07287E22B58C050C0744E1324115F08C0ECF46FB0CBB350C0A5FB01ADEE3301C0', 1334, 1334, 4182, -2.68829999999999991, -66.3950999999999993, 'S 02 41 17', 'O 66 23 42', 180, 103);
INSERT INTO bdc.mux_grid VALUES ('180/104', '0106000020E61000000100000001030000000100000005000000C63B82B258C050C0AB61E99F0E5F08C018016542898450C0CEB307913E7D09C0E01A662C199150C084F04658275410C08E55839CE8CC50C0E68E6FBF1E8A0FC0C63B82B258C050C0AB61E99F0E5F08C0', 1335, 1335, 4183, -3.58429999999999982, -66.5913000000000039, 'S 03 35 03', 'O 66 35 28', 180, 104);
INSERT INTO bdc.mux_grid VALUES ('180/105', '0106000020E61000000100000001030000000100000005000000E44B2752E9CC50C008274D5A1B8A0FC0B8D74B961A9150C034E973F6235410C0361C0300AF9D50C016BDD50CA0E913C06290DEBB7DD950C0696788C3895A13C0E44B2752E9CC50C008274D5A1B8A0FC0', 1336, 1336, 4184, -4.48029999999999973, -66.7878000000000043, 'S 04 28 49', 'O 66 47 15', 180, 105);
INSERT INTO bdc.mux_grid VALUES ('180/106', '0106000020E61000000100000001030000000100000005000000367DDDA07ED950C0CE85AB9F875A13C03C0D56C4B09D50C0CD36ABD29BE913C0F6C922C14AAA50C0F0E66221097F17C0F039AA9D18E650C0F13563EEF4EF16C0367DDDA07ED950C0CE85AB9F875A13C0', 1337, 1337, 4185, -5.37619999999999987, -66.9846000000000004, 'S 05 22 34', 'O 66 59 04', 180, 106);
INSERT INTO bdc.mux_grid VALUES ('180/107', '0106000020E6100000010000000103000000010000000500000070C571B219E650C01D4D3458F2EF16C070F6BBE04CAA50C078A6D90C047F17C0AAFCBE86EDB650C0405CB3C45F141BC0ACCB7458BAF250C0E5020E104E851AC070C571B219E650C01D4D3458F2EF16C0', 1338, 1338, 4186, -6.27210000000000001, -67.1817999999999955, 'S 06 16 19', 'O 67 10 54', 180, 107);
INSERT INTO bdc.mux_grid VALUES ('180/108', '0106000020E610000001000000010300000001000000050000004E038A9DBBF250C048C04E064B851AC0B63CA402F0B650C014EE58D359141BC076994C6B98C350C06A28F423A1A91EC00E60320664FF50C09EFAE956921A1EC04E038A9DBBF250C048C04E064B851AC0', 1339, 1339, 4187, -7.16790000000000038, -67.379400000000004, 'S 07 10 04', 'O 67 22 45', 180, 108);
INSERT INTO bdc.mux_grid VALUES ('180/109', '0106000020E61000000100000001030000000100000005000000C440327C65FF50C0D2C722D88E1A1EC00AA4B1449BC350C0BD5AE8529AA91EC02ECD4C8D4CD050C089B23835651F21C0E869CDC4160C51C013E9D577DFD720C0C440327C65FF50C0D2C722D88E1A1EC0', 1340, 1340, 4189, -8.06359999999999921, -67.5776000000000039, 'S 08 03 49', 'O 67 34 39', 180, 109);
INSERT INTO bdc.mux_grid VALUES ('180/110', '0106000020E610000001000000010300000001000000050000008A846D6C180C51C0DB25157DDDD720C00E7894C54FD050C02FA5315B611F21C0EC8BE20F0BDD50C0E78CA360ECE922C06898BBB6D31851C0930D878268A222C08A846D6C180C51C0DB25157DDDD720C0', 1341, 1341, 4190, -8.95919999999999916, -67.7763999999999953, 'S 08 57 33', 'O 67 46 35', 180, 110);
INSERT INTO bdc.mux_grid VALUES ('180/111', '0106000020E610000001000000010300000001000000050000007AD0CA90D51851C010A4714B66A222C04C3EA0A80EDD50C00DC93813E8E922C076FA6C1BD5E950C0EA8D85A764B424C0A68C97039C2551C0EC68BEDFE26C24C07AD0CA90D51851C010A4714B66A222C0', 1342, 1342, 4192, -9.85479999999999912, -67.9758000000000067, 'S 09 51 17', 'O 67 58 33', 180, 111);
INSERT INTO bdc.mux_grid VALUES ('180/112', '0106000020E6100000010000000103000000010000000500000010F4FE109E2551C0028B3D6BE06C24C03C566616D9E950C0966D98E45FB424C0E87127DEABF650C05173B79BCC7E26C0BC0FC0D8703251C0BD905C224D3726C010F4FE109E2551C0028B3D6BE06C24C0', 1343, 1343, 4193, -10.7501999999999995, -68.1760000000000019, 'S 10 45 00', 'O 68 10 33', 180, 112);
INSERT INTO bdc.mux_grid VALUES ('180/113', '0106000020E61000000100000001030000000100000005000000A4DF831A733251C015F5386F4A3726C08C35563DB0F650C035FAEA60C77E26C074D7CF8C900351C0524D6CCD224928C08C81FD69533F51C03148BADBA50128C0A4DF831A733251C015F5386F4A3726C0', 1344, 1344, 4194, -11.6454000000000004, -68.3769999999999953, 'S 11 38 43', 'O 68 22 37', 180, 113);
INSERT INTO bdc.mux_grid VALUES ('180/114', '0106000020E610000001000000010300000001000000050000008C333EE1553F51C0B9D99AE8A20128C044FC6352950351C008A022181D4928C0620D5463841051C060F4F8CA65132AC0AA442EF2444C51C0112E719BEBCB29C08C333EE1553F51C0B9D99AE8A20128C0', 1345, 1345, 4195, -12.5404999999999998, -68.5788000000000011, 'S 12 32 25', 'O 68 34 43', 180, 114);
INSERT INTO bdc.mux_grid VALUES ('180/115', '0106000020E61000000100000001030000000100000005000000F0CC29A0474C51C05E94D966E8CB29C0AA25B691891051C06E8350985F132AC0445087A5881D51C028F3952094DD2BC08CF7FAB3465951C018041FEF1C962BC0F0CC29A0474C51C05E94D966E8CB29C0', 1346, 1346, 4196, -13.4354999999999993, -68.7817000000000007, 'S 13 26 07', 'O 68 46 54', 180, 115);
INSERT INTO bdc.mux_grid VALUES ('180/116', '0106000020E6100000010000000103000000010000000500000054230E9A495951C0F8FF6D7719962BC0CE2A5B3F8E1D51C0C852666D8DDD2BC03863E09F9E2A51C02E481B58ACA72DC0C05B93FA596651C060F5226238602DC054230E9A495951C0F8FF6D7719962BC0', 1347, 1347, 4197, -14.3302999999999994, -68.9855000000000018, 'S 14 19 49', 'O 68 59 07', 180, 116);
INSERT INTO bdc.mux_grid VALUES ('180/117', '0106000020E6100000010000000103000000010000000500000054563B1A5D6651C0AF8F90A534602DC066F707A8A42A51C08FB1F120A5A72DC0807C41A8C73751C0D663B5F8AC712FC06EDB741A807351C0F641547D3C2A2FC054563B1A5D6651C0AF8F90A534602DC0', 1348, 1348, 4198, -15.2249999999999996, -69.1905000000000001, 'S 15 13 29', 'O 69 11 25', 180, 117);
INSERT INTO bdc.mux_grid VALUES ('180/118', '0106000020E61000000100000001030000000100000005000000C2DB5075837351C09AC9EF79382A2FC0A425E021CE3751C055D7D039A5712FC038F9CA1E054551C0E8534943CA9D30C056AF3B72BA8051C00DCD58E3137A30C0C2DB5075837351C09AC9EF79382A2FC0', 1349, 1349, 4200, -16.1193999999999988, -69.3966999999999956, 'S 16 07 09', 'O 69 23 48', 180, 118);
INSERT INTO bdc.mux_grid VALUES ('180/119', '0106000020E61000000100000001030000000100000005000000A8D30E0ABE8051C087B52FBD117A30C01E08490D0C4551C015D4EF1DC69D30C078F4B96E585251C0C26044C1B08231C002C07F6B0A8E51C034428460FC5E31C0A8D30E0ABE8051C087B52FBD117A30C0', 1350, 1350, 4202, -17.0137, -69.6041000000000025, 'S 17 00 49', 'O 69 36 14', 180, 119);
INSERT INTO bdc.mux_grid VALUES ('180/120', '0106000020E61000000100000001030000000100000005000000D61833420E8E51C01DCBBF14FA5E31C0389BC8D55F5251C08F51CE53AC8231C092F1530FC35F51C0057FD834896732C0306FBE7B719B51C092F8C9F5D64332C0D61833420E8E51C01DCBBF14FA5E31C0', 1351, 1351, 4203, -17.9076999999999984, -69.8130000000000024, 'S 17 54 27', 'O 69 48 46', 180, 120);
INSERT INTO bdc.mux_grid VALUES ('180/121', '0106000020E61000000100000001030000000100000005000000043F6393759B51C016932D83D44332C0B895F1F2CA5F51C0D15DE27C846732C066ECE084466D51C01C6C7DDA524C33C0B2955225F1A851C060A1C8E0A22833C0043F6393759B51C016932D83D44332C0', 1352, 1352, 4204, -18.8016000000000005, -70.0232000000000028, 'S 18 48 05', 'O 70 01 23', 180, 121);
INSERT INTO bdc.mux_grid VALUES ('180/89', '0106000020E610000001000000010300000001000000050000000A0AE2E03E0350C0CA6C055DDBC824401D862AD3F18E4FC05DE75FB55A812440D25287C98AA84FC0FA358258E5B622406670105C0B1050C067BB270066FE22400A0AE2E03E0350C0CA6C055DDBC82440', 1353, 1353, 4266, 9.85479999999999912, -63.6387, 'N 09 51 17', 'O 63 38 19', 180, 89);
INSERT INTO bdc.mux_grid VALUES ('180/90', '0106000020E61000000100000001030000000100000005000000A8B5E042091050C038A68E7D63FE2240E5A521EB82A84FC03F24ABA3E0B62240E938596504C24FC0B95BBA225CEC2040287FFCFFC91C50C0B0DD9DFCDE332140A8B5E042091050C038A68E7D63FE2240', 1354, 1354, 4267, 8.95919999999999916, -63.8382000000000005, 'N 08 57 33', 'O 63 50 17', 180, 90);
INSERT INTO bdc.mux_grid VALUES ('180/91', '0106000020E6100000010000000103000000010000000500000052BB5D1AC81C50C0C128B4B7DC33214005BFF94AFDC14FC035FD21E357EC2040E0F6009C69DB4FC0C8304C588B431E403E57E1427E2950C0DC87700195D21E4052BB5D1AC81C50C0C128B4B7DC332140', 1355, 1355, 4269, 8.06359999999999921, -64.0369000000000028, 'N 08 03 49', 'O 64 02 12', 180, 91);
INSERT INTO bdc.mux_grid VALUES ('180/92', '0106000020E61000000100000001030000000100000005000000AE69E48F7C2950C04AC4BFF090D21E40A491284263DB4FC0D8156ABF83431E40F93F44B2BCF44FC06F33A3BE46AE1A40DA40F247293650C0E0E1F8EF533D1B40AE69E48F7C2950C04AC4BFF090D21E40', 1356, 1356, 4270, 7.16790000000000038, -64.2351000000000028, 'N 07 10 04', 'O 64 14 06', 180, 92);
INSERT INTO bdc.mux_grid VALUES ('180/93', '0106000020E61000000100000001030000000100000005000000B26AC2C6273650C07FC86D56503D1B4061D9D715B7F44FC0BB9F580840AE1A4030DCE9F1FF0650C0FDA9994BED181740325AC02DCC4250C0C1D2AE99FDA71740B26AC2C6273650C07FC86D56503D1B40', 1357, 1357, 4272, 6.27210000000000001, -64.4328000000000003, 'N 06 16 19', 'O 64 25 57', 180, 93);
INSERT INTO bdc.mux_grid VALUES ('180/94', '0106000020E61000000100000001030000000100000005000000A25CA2DDCA4250C07C698975FAA71740D67E0C81FD0650C0CB42A374E71817409C493AB29A1350C0DE89A4D0818313406827D00E684F50C08FB08AD194121440A25CA2DDCA4250C07C698975FAA71740', 1358, 1358, 4273, 5.37619999999999987, -64.6299999999999955, 'N 05 22 34', 'O 64 37 47', 180, 94);
INSERT INTO bdc.mux_grid VALUES ('180/95', '0106000020E61000000100000001030000000100000005000000C47E21EF664F50C06C28462192121440248E879D981350C0E84C2FD67C831340AEED90B02F2050C028E7AA3B0EDC0F404CDE2A02FE5B50C0184FEC681C7D1040C47E21EF664F50C06C28462192121440', 1359, 1359, 4275, 4.48029999999999973, -64.8268000000000058, 'N 04 28 49', 'O 64 49 36', 180, 95);
INSERT INTO bdc.mux_grid VALUES ('180/96', '0106000020E61000000100000001030000000100000005000000FE176112FD5B50C02B6D3D2B1A7D1040C45B08F72D2050C0B891F7FA05DC0F40B8509300C02C50C0C3993A0400B10840F00CEC1B8F6850C062E2BD5F2ECF0940FE176112FD5B50C02B6D3D2B1A7D1040', 1360, 1360, 4276, 3.58429999999999982, -65.0233000000000061, 'N 03 35 03', 'O 65 01 23', 180, 96);
INSERT INTO bdc.mux_grid VALUES ('180/97', '0106000020E610000001000000010300000001000000050000008E37945B8E6850C0DC6C65C72ACF0940F42261A1BE2C50C0351AC973F9B00840201F99B34C3950C0EC641597DE850140BC33CC6D1C7550C093B7B1EA0FA402408E37945B8E6850C0DC6C65C72ACF0940', 1361, 1361, 4277, 2.68829999999999991, -65.2194999999999965, 'N 02 41 17', 'O 65 13 10', 180, 97);
INSERT INTO bdc.mux_grid VALUES ('180/98', '0106000020E6100000010000000103000000010000000500000064688ADC1B7550C036D2A6330DA40240016A15AE4B3950C0993FC2B3D985014074E833D9D64550C05712141E5FB5F43FD8E6A807A78150C09237DD1DC6F1F63F64688ADC1B7550C036D2A6330DA40240', 1362, 1362, 4278, 1.79220000000000002, -65.4154999999999944, 'N 01 47 31', 'O 65 24 55', 180, 98);
INSERT INTO bdc.mux_grid VALUES ('180/99', '0106000020E6100000010000000103000000010000000500000076EA37A5A68150C03D06CC6FC2F1F63F76EEE12CD64550C0FBBD00AD58B5F43F0609B57F5F5250C03E3A4E30C47BD93F04050BF82F8E50C0A2ADBD9DB536E13F76EA37A5A68150C03D06CC6FC2F1F63F', 1363, 1363, 4280, 0.896100000000000008, -65.6114000000000033, 'N 00 53 45', 'O 65 36 41', 180, 99);
INSERT INTO bdc.mux_grid VALUES ('181/100', '0106000020E6100000010000000103000000010000000500000036B50EBEF4CB50C0960D24BEB136E13F686F1526249050C044AC07B6B77BD93F1CFE84AEAC9C50C03D59525307DEDFBFEA437E467DD850C053EA118D5BECD6BF36B50EBEF4CB50C0960D24BEB136E13F', 1364, 1364, 4281, 0, -66.7724000000000046, 'N 00 00 00', 'O 66 46 20', 181, 100);
INSERT INTO bdc.mux_grid VALUES ('181/101', '0106000020E61000000100000001030000000100000005000000D69738417DD850C08375E2565CECD6BF32AACAB3AC9C50C02ACE818906DEDFBF46765C7F35A950C0C1FDAB51EE4DF6BFEA63CA0C06E550C0982704C58311F4BFD69738417DD850C08375E2565CECD6BF', 1365, 1365, 4283, -0.896100000000000008, -66.9682999999999993, 'S 00 53 45', 'O 66 58 05', 181, 101);
INSERT INTO bdc.mux_grid VALUES ('181/102', '0106000020E61000000100000001030000000100000005000000048A0B3606E550C0E1BC373A8211F4BF109C5CDD35A950C03F261ACEEA4DF6BF602EB8F9BFB550C0295B579B245202C0561C675290F150C07B266651F03301C0048A0B3606E550C0E1BC373A8211F4BF', 1366, 1366, 4285, -1.79220000000000002, -67.1641999999999939, 'S 01 47 31', 'O 67 09 51', 181, 102);
INSERT INTO bdc.mux_grid VALUES ('181/103', '0106000020E61000000100000001030000000100000005000000BAA842AA90F150C0F6FB01ADEE3301C0DE839FB0C0B550C0DFA42930215202C06416122C4DC250C0A9F73AA7437D09C03E3BB5251DFE50C0C04E1324115F08C0BAA842AA90F150C0F6FB01ADEE3301C0', 1367, 1367, 4286, -2.68829999999999991, -67.3602000000000061, 'S 02 41 17', 'O 67 21 36', 181, 103);
INSERT INTO bdc.mux_grid VALUES ('181/104', '0106000020E6100000010000000103000000010000000500000092EF54AC1DFE50C0FC61E99F0E5F08C0EAB4373C4EC250C00DB407913E7D09C0B2CE3826DECE50C063F04658275410C05A095696AD0A51C0B48E6FBF1E8A0FC092EF54AC1DFE50C0FC61E99F0E5F08C0', 1368, 1368, 4287, -3.58429999999999982, -67.5563999999999965, 'S 03 35 03', 'O 67 33 23', 181, 104);
INSERT INTO bdc.mux_grid VALUES ('181/105', '0106000020E61000000100000001030000000100000005000000B6FFF94BAE0A51C0C0264D5A1B8A0FC08A8B1E90DFCE50C00EE973F6235410C00AD0D5F973DB50C072BDD50CA0E913C03644B1B5421751C0C46788C3895A13C0B6FFF94BAE0A51C0C0264D5A1B8A0FC0', 1369, 1369, 4288, -4.48029999999999973, -67.7528999999999968, 'S 04 28 49', 'O 67 45 10', 181, 105);
INSERT INTO bdc.mux_grid VALUES ('181/106', '0106000020E610000001000000010300000001000000050000000231B09A431751C03B86AB9F875A13C008C128BE75DB50C03D37ABD29BE913C0C07DF5BA0FE850C0E0E66221097F17C0BAED7C97DD2351C0DF3563EEF4EF16C00231B09A431751C03B86AB9F875A13C0', 1370, 1370, 4289, -5.37619999999999987, -67.9497000000000071, 'S 05 22 34', 'O 67 56 59', 181, 106);
INSERT INTO bdc.mux_grid VALUES ('181/107', '0106000020E61000000100000001030000000100000005000000447944ACDE2351C0F44C3458F2EF16C044AA8EDA11E850C04DA6D90C047F17C080B09180B2F450C0955CB3C45F141BC0827F47527F3051C03C030E104E851AC0447944ACDE2351C0F44C3458F2EF16C0', 1371, 1371, 4291, -6.27210000000000001, -68.1469000000000023, 'S 06 16 19', 'O 68 08 48', 181, 107);
INSERT INTO bdc.mux_grid VALUES ('181/108', '0106000020E6100000010000000103000000010000000500000017B75C97803051C0C1C04E064B851AC090F076FCB4F450C061EE58D359141BC04D4D1F655D0151C0B427F423A1A91EC0D2130500293D51C016FAE956921A1EC017B75C97803051C0C1C04E064B851AC0', 1372, 1372, 4292, -7.16790000000000038, -68.3445999999999998, 'S 07 10 04', 'O 68 20 40', 181, 108);
INSERT INTO bdc.mux_grid VALUES ('181/109', '0106000020E6100000010000000103000000010000000500000094F404762A3D51C02FC722D88E1A1EC0E257843E600151C0055AE8529AA91EC006811F87110E51C02BB23835651F21C0B81DA0BEDB4951C0BFE8D577DFD720C094F404762A3D51C02FC722D88E1A1EC0', 1373, 1373, 4294, -8.06359999999999921, -68.5427999999999997, 'S 08 03 49', 'O 68 32 33', 181, 109);
INSERT INTO bdc.mux_grid VALUES ('181/110', '0106000020E6100000010000000103000000010000000500000058384066DD4951C08B25157DDDD720C0DC2B67BF140E51C0DDA4315B611F21C0C03FB509D01A51C0158DA360ECE922C03C4C8EB0985651C0C20D878268A222C058384066DD4951C08B25157DDDD720C0', 1374, 1374, 4296, -8.95919999999999916, -68.741500000000002, 'S 08 57 33', 'O 68 44 29', 181, 110);
INSERT INTO bdc.mux_grid VALUES ('181/111', '0106000020E6100000010000000103000000010000000500000054849D8A9A5651C036A4714B66A222C014F272A2D31A51C046C93813E8E922C03CAE3F159A2751C0A38D85A764B424C07C406AFD606351C09368BEDFE26C24C054849D8A9A5651C036A4714B66A222C0', 1375, 1375, 4297, -9.85479999999999912, -68.9410000000000025, 'S 09 51 17', 'O 68 56 27', 181, 111);
INSERT INTO bdc.mux_grid VALUES ('181/112', '0106000020E61000000100000001030000000100000005000000E0A7D10A636351C0B08A3D6BE06C24C00D0A39109E2751C0446D98E45FB424C0B825FAD7703451C0FF72B79BCC7E26C08CC392D2357051C06B905C224D3726C0E0A7D10A636351C0B08A3D6BE06C24C0', 1376, 1376, 4298, -10.7501999999999995, -69.1411999999999978, 'S 10 45 00', 'O 69 08 28', 181, 112);
INSERT INTO bdc.mux_grid VALUES ('181/113', '0106000020E6100000010000000103000000010000000500000074935614387051C0C2F4386F4A3726C05CE92837753451C0E4F9EA60C77E26C0468BA286554151C0824D6CCD224928C05E35D063187D51C05F48BADBA50128C074935614387051C0C2F4386F4A3726C0', 1377, 1377, 4299, -11.6454000000000004, -69.3421000000000021, 'S 11 38 43', 'O 69 20 31', 181, 113);
INSERT INTO bdc.mux_grid VALUES ('181/114', '0106000020E6100000010000000103000000010000000500000056E710DB1A7D51C0F2D99AE8A20128C00CB0364C5A4151C042A022181D4928C02CC1265D494E51C09BF4F8CA65132AC074F800EC098A51C04A2E719BEBCB29C056E710DB1A7D51C0F2D99AE8A20128C0', 1378, 1378, 4300, -12.5404999999999998, -69.5439999999999969, 'S 12 32 25', 'O 69 32 38', 181, 114);
INSERT INTO bdc.mux_grid VALUES ('181/115', '0106000020E61000000100000001030000000100000005000000C480FC990C8A51C08994D966E8CB29C07ED9888B4E4E51C0998350985F132AC016045A9F4D5B51C0D3F2952094DD2BC05CABCDAD0B9751C0C3031FEF1C962BC0C480FC990C8A51C08994D966E8CB29C0', 1379, 1379, 4302, -13.4354999999999993, -69.7467999999999932, 'S 13 26 07', 'O 69 44 48', 181, 115);
INSERT INTO bdc.mux_grid VALUES ('181/116', '0106000020E6100000010000000103000000010000000500000022D7E0930E9751C0A7FF6D7719962BC09CDE2D39535B51C07552666D8DDD2BC00A17B399636851C05C481B58ACA72DC0920F66F41EA451C08DF5226238602DC022D7E0930E9751C0A7FF6D7719962BC0', 1380, 1380, 4303, -14.3302999999999994, -69.9506999999999977, 'S 14 19 49', 'O 69 57 02', 181, 116);
INSERT INTO bdc.mux_grid VALUES ('181/117', '0106000020E61000000100000001030000000100000005000000100A0E1422A451C0F78F90A534602DC044ABDAA1696851C0AFB1F120A5A72DC0583014A28C7551C0F662B5F8AC712FC0228F471445B151C04041547D3C2A2FC0100A0E1422A451C0F78F90A534602DC0', 1381, 1381, 4304, -15.2249999999999996, -70.1556000000000068, 'S 15 13 29', 'O 70 09 20', 181, 117);
INSERT INTO bdc.mux_grid VALUES ('181/118', '0106000020E610000001000000010300000001000000050000008A8F236F48B151C0CCC8EF79382A2FC08ED9B21B937551C05CD6D039A5712FC024AD9D18CA8251C06C534943CA9D30C020630E6C7FBE51C0A5CC58E3137A30C08A8F236F48B151C0CCC8EF79382A2FC0', 1382, 1382, 4307, -16.1193999999999988, -70.3618000000000023, 'S 16 07 09', 'O 70 21 42', 181, 118);
INSERT INTO bdc.mux_grid VALUES ('181/119', '0106000020E610000001000000010300000001000000050000008E87E10383BE51C011B52FBD117A30C0E0BB1B07D18251C0B4D3EF1DC69D30C040A88C681D9051C0DF6044C1B08231C0EE735265CFCB51C03C428460FC5E31C08E87E10383BE51C011B52FBD117A30C0', 1383, 1383, 4308, -17.0137, -70.5692999999999984, 'S 17 00 49', 'O 70 34 09', 181, 119);
INSERT INTO bdc.mux_grid VALUES ('181/120', '0106000020E61000000100000001030000000100000005000000BCCC053CD3CB51C02ACBBF14FA5E31C0FA4E9BCF249051C0B151CE53AC8231C05CA52609889D51C0A67FD834896732C01E23917536D951C01EF9C9F5D64332C0BCCC053CD3CB51C02ACBBF14FA5E31C0', 1384, 1384, 4309, -17.9076999999999984, -70.7780999999999949, 'S 17 54 27', 'O 70 46 41', 181, 120);
INSERT INTO bdc.mux_grid VALUES ('181/89', '0106000020E61000000100000001030000000100000005000000DABDB4DA034150C04C6D055DDBC82440E4F667E33D0550C0E7E75FB55A812440425D965E0A1250C023368258E5B622403A24E355D04D50C088BB270066FE2240DABDB4DA034150C04C6D055DDBC82440', 1385, 1385, 4366, 9.85479999999999912, -64.6038999999999959, 'N 09 51 17', 'O 64 36 13', 181, 89);
INSERT INTO bdc.mux_grid VALUES ('181/90', '0106000020E610000001000000010300000001000000050000007069B33CCE4D50C04CA68E7D63FE2240BC86636F061250C05624ABA3E0B622403C507F2CC71E50C0035CBA225CEC2040F032CFF98E5A50C0F9DD9DFCDE3321407069B33CCE4D50C04CA68E7D63FE2240', 1386, 1386, 4368, 8.95919999999999916, -64.803299999999993, 'N 08 57 33', 'O 64 48 11', 181, 90);
INSERT INTO bdc.mux_grid VALUES ('181/91', '0106000020E61000000100000001030000000100000005000000246F30148D5A50C01729B4B7DC33214044934F9FC31E50C076FD21E357EC2040322FD3C7792B50C0CA304C588B431E40120BB43C436750C00588700195D21E40246F30148D5A50C01729B4B7DC332140', 1387, 1387, 4369, 8.06359999999999921, -65.0020999999999987, 'N 08 03 49', 'O 65 00 07', 181, 91);
INSERT INTO bdc.mux_grid VALUES ('181/92', '0106000020E61000000100000001030000000100000005000000861DB789416750C07BC4BFF090D21E40A0FCE69A762B50C0F2156ABF83431E40CCD3F452233850C00833A3BE46AE1A40B2F4C441EE7350C091E1F8EF533D1B40861DB789416750C07BC4BFF090D21E40', 1388, 1388, 4370, 7.16790000000000038, -65.2002999999999986, 'N 07 10 04', 'O 65 12 00', 181, 92);
INSERT INTO bdc.mux_grid VALUES ('181/93', '0106000020E61000000100000001030000000100000005000000841E95C0EC7350C01DC86D56503D1B4082A0BE84203850C05C9F580840AE1A400290BCEBC44450C09EA9994BED181740040E9327918050C05ED2AE99FDA71740841E95C0EC7350C01DC86D56503D1B40', 1389, 1389, 4372, 6.27210000000000001, -65.397900000000007, 'N 06 16 19', 'O 65 23 52', 181, 93);
INSERT INTO bdc.mux_grid VALUES ('181/94', '0106000020E61000000100000001030000000100000005000000781075D78F8050C029698975FAA71740A432DF7AC24450C06442A374E71817406AFD0CAC5F5150C0F789A4D0818313403EDBA2082D8D50C0BBB08AD194121440781075D78F8050C029698975FAA71740', 1390, 1390, 4374, 5.37619999999999987, -65.5951000000000022, 'N 05 22 34', 'O 65 35 42', 181, 94);
INSERT INTO bdc.mux_grid VALUES ('181/95', '0106000020E610000001000000010300000001000000050000009632F4E82B8D50C08F28462192121440F8415A975D5150C00E4D2FD67C83134082A163AAF45D50C075E6AA3B0EDC0F402292FDFBC29950C0BC4EEC681C7D10409632F4E82B8D50C08F28462192121440', 1391, 1391, 4375, 4.48029999999999973, -65.7918999999999983, 'N 04 28 49', 'O 65 47 30', 181, 95);
INSERT INTO bdc.mux_grid VALUES ('181/96', '0106000020E61000000100000001030000000100000005000000D2CB330CC29950C0D26C3D2B1A7D1040960FDBF0F25D50C0F390F7FA05DC0F40860466FA846A50C0FD993A0400B10840C4C0BE1554A650C0B2E2BD5F2ECF0940D2CB330CC29950C0D26C3D2B1A7D1040', 1392, 1392, 4376, 3.58429999999999982, -65.9883999999999986, 'N 03 35 03', 'O 65 59 18', 181, 96);
INSERT INTO bdc.mux_grid VALUES ('181/97', '0106000020E6100000010000000103000000010000000500000064EB665553A650C0336D65C72ACF0940C4D6339B836A50C0751AC973F9B00840F2D26BAD117750C0AD641597DE85014090E79E67E1B250C06BB7B1EA0FA4024064EB665553A650C0336D65C72ACF0940', 1393, 1393, 4377, 2.68829999999999991, -66.1846000000000032, 'N 02 41 17', 'O 66 11 04', 181, 97);
INSERT INTO bdc.mux_grid VALUES ('181/98', '0106000020E61000000100000001030000000100000005000000361C5DD6E0B250C0FCD1A6330DA40240D41DE8A7107750C0683FC2B3D9850140489C06D39B8350C0F912141E5FB5F43FAA9A7B016CBF50C02138DD1DC6F1F63F361C5DD6E0B250C0FCD1A6330DA40240', 1394, 1394, 4379, 1.79220000000000002, -66.3807000000000045, 'N 01 47 31', 'O 66 22 50', 181, 98);
INSERT INTO bdc.mux_grid VALUES ('181/99', '0106000020E61000000100000001030000000100000005000000469E0A9F6BBF50C0C806CC6FC2F1F63F48A2B4269B8350C086BE00AD58B5F43FD6BC8779249050C0853A4E30C47BD93FD6B8DDF1F4CB50C0C6ADBD9DB536E13F469E0A9F6BBF50C0C806CC6FC2F1F63F', 1395, 1395, 4380, 0.896100000000000008, -66.5765999999999991, 'N 00 53 45', 'O 66 34 35', 181, 99);
INSERT INTO bdc.mux_grid VALUES ('182/100', '0106000020E610000001000000010300000001000000050000000869E1B7B90951C0900D24BEB136E13F3A23E81FE9CD50C062AC07B6B77BD93FEEB157A871DA50C05259525307DEDFBFBCF75040421651C095EA118D5BECD6BF0869E1B7B90951C0900D24BEB136E13F', 1396, 1396, 4381, 0, -67.7376000000000005, 'N 00 00 00', 'O 67 44 15', 182, 100);
INSERT INTO bdc.mux_grid VALUES ('182/101', '0106000020E61000000100000001030000000100000005000000A64B0B3B421651C0C475E2565CECD6BF045E9DAD71DA50C042CE818906DEDFBF182A2F79FAE650C0B0FDAB51EE4DF6BFBC179D06CB2251C0902704C58311F4BFA64B0B3B421651C0C475E2565CECD6BF', 1397, 1397, 4384, -0.896100000000000008, -67.933400000000006, 'S 00 53 45', 'O 67 56 00', 182, 101);
INSERT INTO bdc.mux_grid VALUES ('182/102', '0106000020E61000000100000001030000000100000005000000D83DDE2FCB2251C0C8BC373A8211F4BFDE4F2FD7FAE650C049261ACEEA4DF6BF30E28AF384F350C0FB5A579B245202C02AD0394C552F51C03B266651F03301C0D83DDE2FCB2251C0C8BC373A8211F4BF', 1398, 1398, 4385, -1.79220000000000002, -68.1293000000000006, 'S 01 47 31', 'O 68 07 45', 182, 102);
INSERT INTO bdc.mux_grid VALUES ('182/103', '0106000020E61000000100000001030000000100000005000000905C15A4552F51C0AEFB01ADEE3301C0AA3772AA85F350C0BEA42930215202C032CAE425120051C016F83AA7437D09C016EF871FE23B51C0054F1324115F08C0905C15A4552F51C0AEFB01ADEE3301C0', 1399, 1399, 4386, -2.68829999999999991, -68.3254000000000019, 'S 02 41 17', 'O 68 19 31', 182, 103);
INSERT INTO bdc.mux_grid VALUES ('182/104', '0106000020E6100000010000000103000000010000000500000068A327A6E23B51C04562E99F0E5F08C0B6680A36130051C07BB407913E7D09C07E820B20A30C51C0E0F04658275410C030BD2890724851C08B8F6FBF1E8A0FC068A327A6E23B51C04562E99F0E5F08C0', 1400, 1400, 4387, -3.58429999999999982, -68.5216000000000065, 'S 03 35 03', 'O 68 31 17', 182, 104);
INSERT INTO bdc.mux_grid VALUES ('182/105', '0106000020E6100000010000000103000000010000000500000082B3CC45734851C0C8274D5A1B8A0FC05E3FF189A40C51C07DE973F6235410C0DC83A8F3381951C062BDD50CA0E913C000F883AF075551C0C96788C3895A13C082B3CC45734851C0C8274D5A1B8A0FC0', 1401, 1401, 4388, -4.48029999999999973, -68.7181000000000068, 'S 04 28 49', 'O 68 43 05', 182, 105);
INSERT INTO bdc.mux_grid VALUES ('182/106', '0106000020E61000000100000001030000000100000005000000D6E48294085551C02786AB9F875A13C0D274FBB73A1951C03D37ABD29BE913C08C31C8B4D42551C027E76221097F17C08EA14F91A26151C0123663EEF4EF16C0D6E48294085551C02786AB9F875A13C0', 1402, 1402, 4390, -5.37619999999999987, -68.9149000000000029, 'S 05 22 34', 'O 68 54 53', 182, 106);
INSERT INTO bdc.mux_grid VALUES ('182/107', '0106000020E61000000100000001030000000100000005000000122D17A6A36151C0394D3458F2EF16C01A5E61D4D62551C07EA6D90C047F17C05664647A773251C08B5CB3C45F141BC04E331A4C446E51C046030E104E851AC0122D17A6A36151C0394D3458F2EF16C0', 1403, 1403, 4391, -6.27210000000000001, -69.1120999999999981, 'S 06 16 19', 'O 69 06 43', 182, 107);
INSERT INTO bdc.mux_grid VALUES ('182/108', '0106000020E61000000100000001030000000100000005000000EE6A2F91456E51C0AEC04E064B851AC056A449F6793251C079EE58D359141BC01601F25E223F51C09228F423A1A91EC0AEC7D7F9ED7A51C0C5FAE956921A1EC0EE6A2F91456E51C0AEC04E064B851AC0', 1404, 1404, 4392, -7.16790000000000038, -69.3097000000000065, 'S 07 10 04', 'O 69 18 35', 182, 108);
INSERT INTO bdc.mux_grid VALUES ('182/109', '0106000020E610000001000000010300000001000000050000006AA8D76FEF7A51C0F0C722D88E1A1EC0B60B5738253F51C0C65AE8529AA91EC0DC34F280D64B51C0B3B23835651F21C08ED172B8A08751C048E9D577DFD720C06AA8D76FEF7A51C0F0C722D88E1A1EC0', 1405, 1405, 4395, -8.06359999999999921, -69.5079000000000065, 'S 08 03 49', 'O 69 30 28', 182, 109);
INSERT INTO bdc.mux_grid VALUES ('182/110', '0106000020E6100000010000000103000000010000000500000030EC1260A28751C01226157DDDD720C0B2DF39B9D94B51C065A5315B611F21C092F38703955851C0FF8CA360ECE922C00E0061AA5D9451C0AD0D878268A222C030EC1260A28751C01226157DDDD720C0', 1406, 1406, 4396, -8.95919999999999916, -69.7066999999999979, 'S 08 57 33', 'O 69 42 24', 182, 110);
INSERT INTO bdc.mux_grid VALUES ('182/111', '0106000020E610000001000000010300000001000000050000001B3870845F9451C02CA4714B66A222C0EAA5459C985851C028C93813E8E922C01462120F5F6551C0E78D85A764B424C044F43CF725A151C0EB68BEDFE26C24C01B3870845F9451C02CA4714B66A222C0', 1407, 1407, 4397, -9.85479999999999912, -69.906099999999995, 'S 09 51 17', 'O 69 54 22', 182, 111);
INSERT INTO bdc.mux_grid VALUES ('182/112', '0106000020E61000000100000001030000000100000005000000B45BA40428A151C0FB8A3D6BE06C24C0E0BD0B0A636551C08E6D98E45FB424C08CD9CCD1357251C02B73B79BCC7E26C0607765CCFAAD51C099905C224D3726C0B45BA40428A151C0FB8A3D6BE06C24C0', 1408, 1408, 4398, -10.7501999999999995, -70.1063000000000045, 'S 10 45 00', 'O 70 06 22', 182, 112);
INSERT INTO bdc.mux_grid VALUES ('182/113', '0106000020E610000001000000010300000001000000050000004447290EFDAD51C0F3F4386F4A3726C02E9DFB303A7251C014FAEA60C77E26C0163F75801A7F51C0934D6CCD224928C02EE9A25DDDBA51C07248BADBA50128C04447290EFDAD51C0F3F4386F4A3726C0', 1409, 1409, 4399, -11.6454000000000004, -70.3072999999999979, 'S 11 38 43', 'O 70 18 26', 182, 113);
INSERT INTO bdc.mux_grid VALUES ('182/114', '0106000020E61000000100000001030000000100000005000000309BE3D4DFBA51C0FDD99AE8A20128C0D66309461F7F51C061A022181D4928C0F474F9560E8C51C09AF4F8CA65132AC04EACD3E5CEC751C0352E719BEBCB29C0309BE3D4DFBA51C0FDD99AE8A20128C0', 1410, 1410, 4401, -12.5404999999999998, -70.5091000000000037, 'S 12 32 25', 'O 70 30 32', 182, 114);
INSERT INTO bdc.mux_grid VALUES ('182/115', '0106000020E610000001000000010300000001000000050000009834CF93D1C751C07B94D966E8CB29C0508D5B85138C51C08A8350985F132AC0E8B72C99129951C0A6F2952094DD2BC02E5FA0A7D0D451C098031FEF1C962BC09834CF93D1C751C07B94D966E8CB29C0', 1411, 1411, 4402, -13.4354999999999993, -70.7120000000000033, 'S 13 26 07', 'O 70 42 43', 182, 115);
INSERT INTO bdc.mux_grid VALUES ('182/116', '0106000020E61000000100000001030000000100000005000000048BB38DD3D451C06BFF6D7719962BC06C920033189951C04D52666D8DDD2BC0DECA859328A651C097481B58ACA72DC076C338EEE3E151C0B6F5226238602DC0048BB38DD3D451C06BFF6D7719962BC0', 1412, 1412, 4403, -14.3302999999999994, -70.9158000000000044, 'S 14 19 49', 'O 70 54 56', 182, 116);
INSERT INTO bdc.mux_grid VALUES ('182/117', '0106000020E61000000100000001030000000100000005000000F1BDE00DE7E151C0249090A534602DC0025FAD9B2EA651C003B2F120A5A72DC014E4E69B51B351C02C63B5F8AC712FC002431A0E0AEF51C04C41547D3C2A2FC0F1BDE00DE7E151C0249090A534602DC0', 1413, 1413, 4404, -15.2249999999999996, -71.1208000000000027, 'S 15 13 29', 'O 71 07 14', 182, 117);
INSERT INTO bdc.mux_grid VALUES ('182/118', '0106000020E610000001000000010300000001000000050000005A43F6680DEF51C0EBC8EF79382A2FC05E8D851558B351C078D6D039A5712FC0FA6070128FC051C0E0534943CA9D30C0F416E16544FC51C017CD58E3137A30C05A43F6680DEF51C0EBC8EF79382A2FC0', 1414, 1414, 4407, -16.1193999999999988, -71.3269999999999982, 'S 16 07 09', 'O 71 19 37', 182, 118);
INSERT INTO bdc.mux_grid VALUES ('182/119', '0106000020E610000001000000010300000001000000050000005A3BB4FD47FC51C087B52FBD117A30C0D06FEE0096C051C018D4EF1DC69D30C0225C5F62E2CD51C0336044C1B08231C0AC27255F940952C0A4418460FC5E31C05A3BB4FD47FC51C087B52FBD117A30C0', 1415, 1415, 4408, -17.0137, -71.5344000000000051, 'S 17 00 49', 'O 71 32 03', 182, 119);
INSERT INTO bdc.mux_grid VALUES ('182/89', '0106000020E61000000100000001030000000100000005000000B27187D4C87E50C0DC6C055DDBC82440BCAA3ADD024350C079E75FB55A81244016116958CF4F50C053368258E5B622400ED8B54F958B50C0B7BB270066FE2240B27187D4C87E50C0DC6C055DDBC82440', 1416, 1416, 4464, 9.85479999999999912, -65.5690000000000026, 'N 09 51 17', 'O 65 34 08', 182, 89);
INSERT INTO bdc.mux_grid VALUES ('182/90', '0106000020E610000001000000010300000001000000050000004A1D8636938B50C083A68E7D63FE2240843A3669CB4F50C07924ABA3E0B62240020452268C5C50C0425CBA225CEC2040C8E6A1F3539850C04DDE9DFCDE3321404A1D8636938B50C083A68E7D63FE2240', 1417, 1417, 4465, 8.95919999999999916, -65.7685000000000031, 'N 08 57 33', 'O 65 46 06', 182, 90);
INSERT INTO bdc.mux_grid VALUES ('182/91', '0106000020E61000000100000001030000000100000005000000F822030E529850C06429B4B7DC33214018472299885C50C0C6FD21E357EC204008E3A5C13E6950C0A2304C588B431E40E8BE863608A550C0E087700195D21E40F822030E529850C06429B4B7DC332140', 1418, 1418, 4466, 8.06359999999999921, -65.9672000000000054, 'N 08 03 49', 'O 65 58 02', 182, 91);
INSERT INTO bdc.mux_grid VALUES ('182/92', '0106000020E6100000010000000103000000010000000500000055D1898306A550C045C4BFF090D21E4078B0B9943B6950C0D1156ABF83431E40A487C74CE87550C02233A3BE46AE1A4080A8973BB3B150C094E1F8EF533D1B4055D1898306A550C045C4BFF090D21E40', 1419, 1419, 4467, 7.16790000000000038, -66.1654000000000053, 'N 07 10 04', 'O 66 09 55', 182, 92);
INSERT INTO bdc.mux_grid VALUES ('182/93', '0106000020E6100000010000000103000000010000000500000054D267BAB1B150C025C86D56503D1B405254917EE57550C0619F580840AE1A40D2438FE5898250C05EA9994BED181740D4C1652156BE50C022D2AE99FDA7174054D267BAB1B150C025C86D56503D1B40', 1420, 1420, 4470, 6.27210000000000001, -66.3631000000000029, 'N 06 16 19', 'O 66 21 47', 182, 93);
INSERT INTO bdc.mux_grid VALUES ('182/94', '0106000020E6100000010000000103000000010000000500000050C447D154BE50C0FB688975FAA717407CE6B174878250C03442A374E718174040B1DFA5248F50C0028AA4D081831340148F7502F2CA50C0C8B08AD19412144050C447D154BE50C0FB688975FAA71740', 1421, 1421, 4471, 5.37619999999999987, -66.560299999999998, 'N 05 22 34', 'O 66 33 36', 182, 94);
INSERT INTO bdc.mux_grid VALUES ('182/95', '0106000020E6100000010000000103000000010000000500000070E6C6E2F0CA50C0A828462192121440CAF52C91228F50C0104D2FD67C831340555536A4B99B50C0F1E6AA3B0EDC0F40FA45D0F587D750C00F4FEC681C7D104070E6C6E2F0CA50C0A828462192121440', 1422, 1422, 4472, 4.48029999999999973, -66.7570999999999941, 'N 04 28 49', 'O 66 45 25', 182, 95);
INSERT INTO bdc.mux_grid VALUES ('182/96', '0106000020E61000000100000001030000000100000005000000A27F060687D750C00A6D3D2B1A7D104068C3ADEAB79B50C07491F7FA05DC0F405AB838F449A850C0F6993A0400B108409474910F19E450C094E2BD5F2ECF0940A27F060687D750C00A6D3D2B1A7D1040', 1423, 1423, 4473, 3.58429999999999982, -66.9535999999999945, 'N 03 35 03', 'O 66 57 12', 182, 96);
INSERT INTO bdc.mux_grid VALUES ('182/97', '0106000020E61000000100000001030000000100000005000000349F394F18E450C0196D65C72ACF0940988A069548A850C0721AC973F9B00840C6863EA7D6B450C0A1641597DE850140629B7161A6F050C048B7B1EA0FA40240349F394F18E450C0196D65C72ACF0940', 1424, 1424, 4474, 2.68829999999999991, -67.149799999999999, 'N 02 41 17', 'O 67 08 59', 182, 97);
INSERT INTO bdc.mux_grid VALUES ('182/98', '0106000020E6100000010000000103000000010000000500000009D02FD0A5F050C0DFD1A6330DA40240A6D1BAA1D5B450C04A3FC2B3D98501401A50D9CC60C150C03613141E5FB5F43F7A4E4EFB30FD50C05D38DD1DC6F1F63F09D02FD0A5F050C0DFD1A6330DA40240', 1425, 1425, 4475, 1.79220000000000002, -67.345799999999997, 'N 01 47 31', 'O 67 20 44', 182, 98);
INSERT INTO bdc.mux_grid VALUES ('182/99', '0106000020E610000001000000010300000001000000050000001852DD9830FD50C00907CC6FC2F1F63F1856872060C150C0BEBE00AD58B5F43FA8705A73E9CD50C07F3A4E30C47BD93FA86CB0EBB90951C0C0ADBD9DB536E13F1852DD9830FD50C00907CC6FC2F1F63F', 1426, 1426, 4476, 0.896100000000000008, -67.5417000000000058, 'N 00 53 45', 'O 67 32 30', 182, 99);
INSERT INTO bdc.mux_grid VALUES ('183/100', '0106000020E61000000100000001030000000100000005000000D81CB4B17E4751C0F00D24BEB136E13F0DD7BA19AE0B51C03FAD07B6B77BD93FC0652AA2361851C03D59525307DEDFBF8CAB233A075451C09BEA118D5BECD6BFD81CB4B17E4751C0F00D24BEB136E13F', 1427, 1427, 4477, 0, -68.702699999999993, 'N 00 00 00', 'O 68 42 09', 183, 100);
INSERT INTO bdc.mux_grid VALUES ('183/101', '0106000020E6100000010000000103000000010000000500000076FFDD34075451C0EF75E2565CECD6BFD41170A7361851C02ACE818906DEDFBFEADD0173BF2451C024FEAB51EE4DF6BF8CCB6F00906051C0152804C58311F4BF76FFDD34075451C0EF75E2565CECD6BF', 1428, 1428, 4480, -0.896100000000000008, -68.8986000000000018, 'S 00 53 45', 'O 68 53 54', 183, 101);
INSERT INTO bdc.mux_grid VALUES ('183/102', '0106000020E61000000100000001030000000100000005000000A8F1B029906051C043BD373A8211F4BFB20302D1BF2451C0A2261ACEEA4DF6BF02965DED493151C0175B579B245202C0F8830C461A6D51C068266651F03301C0A8F1B029906051C043BD373A8211F4BF', 1429, 1429, 4481, -1.79220000000000002, -69.0944999999999965, 'S 01 47 31', 'O 69 05 40', 183, 102);
INSERT INTO bdc.mux_grid VALUES ('183/103', '0106000020E610000001000000010300000001000000050000006010E89D1A6D51C0D2FB01ADEE3301C082EB44A44A3151C0D2A42930215202C0087EB71FD73D51C01EF83AA7437D09C0E8A25A19A77951C01E4F1324115F08C06010E89D1A6D51C0D2FB01ADEE3301C0', 1430, 1430, 4482, -2.68829999999999991, -69.2904999999999944, 'S 02 41 17', 'O 69 17 25', 183, 103);
INSERT INTO bdc.mux_grid VALUES ('183/104', '0106000020E610000001000000010300000001000000050000003657FA9FA77951C07562E99F0E5F08C08C1CDD2FD83D51C086B407913E7D09C05436DE19684A51C09FF04658275410C0FC70FB89378651C02E8F6FBF1E8A0FC03657FA9FA77951C07562E99F0E5F08C0', 1431, 1431, 4483, -3.58429999999999982, -69.486699999999999, 'S 03 35 03', 'O 69 29 12', 183, 104);
INSERT INTO bdc.mux_grid VALUES ('183/105', '0106000020E6100000010000000103000000010000000500000054679F3F388651C053274D5A1B8A0FC028F3C383694A51C05BE973F6235410C0A6377BEDFD5651C03EBDD50CA0E913C0D2AB56A9CC9251C08F6788C3895A13C054679F3F388651C053274D5A1B8A0FC0', 1432, 1432, 4485, -4.48029999999999973, -69.6831999999999994, 'S 04 28 49', 'O 69 40 59', 183, 105);
INSERT INTO bdc.mux_grid VALUES ('183/106', '0106000020E61000000100000001030000000100000005000000A898558ECD9251C0EB85AB9F875A13C0A628CEB1FF5651C00337ABD29BE913C05EE59AAE996351C028E76221097F17C06055228B679F51C0103663EEF4EF16C0A898558ECD9251C0EB85AB9F875A13C0', 1433, 1433, 4486, -5.37619999999999987, -69.8799999999999955, 'S 05 22 34', 'O 69 52 48', 183, 106);
INSERT INTO bdc.mux_grid VALUES ('183/107', '0106000020E61000000100000001030000000100000005000000DEE0E99F689F51C0494D3458F2EF16C0E41134CE9B6351C08EA6D90C047F17C0221837743C7051C0D85CB3C45F141BC01AE7EC4509AC51C093030E104E851AC0DEE0E99F689F51C0494D3458F2EF16C0', 1434, 1434, 4487, -6.27210000000000001, -70.0772000000000048, 'S 06 16 19', 'O 70 04 38', 183, 107);
INSERT INTO bdc.mux_grid VALUES ('183/108', '0106000020E61000000100000001030000000100000005000000BE1E028B0AAC51C0F0C04E064B851AC030581CF03E7051C0A6EE58D359141BC0ECB4C458E77C51C07B27F423A1A91EC07A7BAAF3B2B851C0C5F9E956921A1EC0BE1E028B0AAC51C0F0C04E064B851AC0', 1435, 1435, 4488, -7.16790000000000038, -70.2749000000000024, 'S 07 10 04', 'O 70 16 29', 183, 108);
INSERT INTO bdc.mux_grid VALUES ('183/109', '0106000020E61000000100000001030000000100000005000000365CAA69B4B851C0E9C622D88E1A1EC084BF2932EA7C51C0C159E8529AA91EC0ACE8C47A9B8951C087B23835651F21C05E8545B265C551C01AE9D577DFD720C0365CAA69B4B851C0E9C622D88E1A1EC0', 1436, 1436, 4491, -8.06359999999999921, -70.4731000000000023, 'S 08 03 49', 'O 70 28 23', 183, 109);
INSERT INTO bdc.mux_grid VALUES ('183/110', '0106000020E61000000100000001030000000100000005000000FE9FE55967C551C0E425157DDDD720C082930CB39E8951C038A5315B611F21C064A75AFD599651C0708DA360ECE922C0E2B333A422D251C01C0E878268A222C0FE9FE55967C551C0E425157DDDD720C0', 1437, 1437, 4492, -8.95919999999999916, -70.6718000000000046, 'S 08 57 33', 'O 70 40 18', 183, 110);
INSERT INTO bdc.mux_grid VALUES ('183/111', '0106000020E61000000100000001030000000100000005000000F6EB427E24D251C097A4714B66A222C0B65918965D9651C0A8C93813E8E922C0DC15E50824A351C0038E85A764B424C01EA80FF1EADE51C0F268BEDFE26C24C0F6EB427E24D251C097A4714B66A222C0', 1438, 1438, 4493, -9.85479999999999912, -70.8713000000000051, 'S 09 51 17', 'O 70 52 16', 183, 111);
INSERT INTO bdc.mux_grid VALUES ('183/112', '0106000020E61000000100000001030000000100000005000000760F77FEECDE51C01D8B3D6BE06C24C0B271DE0328A351C09C6D98E45FB424C05E8D9FCBFAAF51C05B73B79BCC7E26C0222B38C6BFEB51C0DA905C224D3726C0760F77FEECDE51C01D8B3D6BE06C24C0', 1439, 1439, 4494, -10.7501999999999995, -71.071399999999997, 'S 10 45 00', 'O 71 04 17', 183, 112);
INSERT INTO bdc.mux_grid VALUES ('183/113', '0106000020E6100000010000000103000000010000000500000018FBFB07C2EB51C020F5386F4A3726C00051CE2AFFAF51C041FAEA60C77E26C0E6F2477ADFBC51C05E4D6CCD224928C0FE9C7557A2F851C03D48BADBA50128C018FBFB07C2EB51C020F5386F4A3726C0', 1440, 1440, 4496, -11.6454000000000004, -71.2724000000000046, 'S 11 38 43', 'O 71 16 20', 183, 113);
INSERT INTO bdc.mux_grid VALUES ('183/114', '0106000020E61000000100000001030000000100000005000000064FB6CEA4F851C0BDD99AE8A20128C0AE17DC3FE4BC51C021A022181D4928C0CC28CC50D3C951C079F4F8CA65132AC02660A6DF930552C0142E719BEBCB29C0064FB6CEA4F851C0BDD99AE8A20128C0', 1441, 1441, 4497, -12.5404999999999998, -71.4742999999999995, 'S 12 32 25', 'O 71 28 27', 183, 114);
INSERT INTO bdc.mux_grid VALUES ('183/115', '0106000020E610000001000000010300000001000000050000006AE8A18D960552C06194D966E8CB29C024412E7FD8C951C0718350985F132AC0BA6BFF92D7D651C0ABF2952094DD2BC0021373A1951252C09B031FEF1C962BC06AE8A18D960552C06194D966E8CB29C0', 1442, 1442, 4498, -13.4354999999999993, -71.6770999999999958, 'S 13 26 07', 'O 71 40 37', 183, 115);
INSERT INTO bdc.mux_grid VALUES ('183/116', '0106000020E61000000100000001030000000100000005000000C23E8687981252C085FF6D7719962BC04E46D32CDDD651C03F52666D8DDD2BC0C07E588DEDE351C0A7481B58ACA72DC034770BE8A81F52C0EDF5226238602DC0C23E8687981252C085FF6D7719962BC0', 1443, 1443, 4499, -14.3302999999999994, -71.8810000000000002, 'S 14 19 49', 'O 71 52 51', 183, 116);
INSERT INTO bdc.mux_grid VALUES ('183/117', '0106000020E61000000100000001030000000100000005000000CE71B307AC1F52C0379090A534602DC0E0128095F3E351C017B2F120A5A72DC0F297B99516F151C05E63B5F8AC712FC0E0F6EC07CF2C52C07E41547D3C2A2FC0CE71B307AC1F52C0379090A534602DC0', 1444, 1444, 4501, -15.2249999999999996, -72.0858999999999952, 'S 15 13 29', 'O 72 05 09', 183, 117);
INSERT INTO bdc.mux_grid VALUES ('183/118', '0106000020E6100000010000000103000000010000000500000008F7C862D22C52C058C9EF79382A2FC02E41580F1DF151C0BDD6D039A5712FC0C414430C54FE51C09F534943CA9D30C09ECAB35F093A52C0ECCC58E3137A30C008F7C862D22C52C058C9EF79382A2FC0', 1445, 1445, 4503, -16.1193999999999988, -72.2921000000000049, 'S 16 07 09', 'O 72 17 31', 183, 118);
INSERT INTO bdc.mux_grid VALUES ('183/89', '0106000020E6100000010000000103000000010000000500000086255ACE8DBC50C0F56C055DDBC82440905E0DD7C78050C090E75FB55A812440EEC43B52948D50C0CD358258E5B62240E48B88495AC950C032BB270066FE224086255ACE8DBC50C0F56C055DDBC82440', 1446, 1446, 4555, 9.85479999999999912, -66.5341999999999985, 'N 09 51 17', 'O 66 32 02', 183, 89);
INSERT INTO bdc.mux_grid VALUES ('183/90', '0106000020E6100000010000000103000000010000000500000018D1583058C950C0F2A58E7D63FE224064EE0863908D50C0FB23ABA3E0B62240DEB72420519A50C0295CBA225CEC2040929A74ED18D650C01FDE9DFCDE33214018D1583058C950C0F2A58E7D63FE2240', 1447, 1447, 4556, 8.95919999999999916, -66.7335999999999956, 'N 08 57 33', 'O 66 44 00', 183, 90);
INSERT INTO bdc.mux_grid VALUES ('183/91', '0106000020E61000000100000001030000000100000005000000BCD6D50717D650C03029B4B7DC332140EEFAF4924D9A50C0A4FD21E357EC2040DE9678BB03A750C0A0304C588B431E40AC725930CDE250C0B587700195D21E40BCD6D50717D650C03029B4B7DC332140', 1448, 1448, 4557, 8.06359999999999921, -66.9324000000000012, 'N 08 03 49', 'O 66 55 56', 183, 91);
INSERT INTO bdc.mux_grid VALUES ('183/92', '0106000020E6100000010000000103000000010000000500000022855C7DCBE250C02FC4BFF090D21E4046648C8E00A750C0BE156ABF83431E40723B9A46ADB350C0D532A3BE46AE1A40505C6A3578EF50C046E1F8EF533D1B4022855C7DCBE250C02FC4BFF090D21E40', 1449, 1449, 4558, 7.16790000000000038, -67.1306000000000012, 'N 07 10 04', 'O 67 07 50', 183, 92);
INSERT INTO bdc.mux_grid VALUES ('183/93', '0106000020E6100000010000000103000000010000000500000024863AB476EF50C0D9C76D56503D1B4022086478AAB350C0189F580840AE1A40A2F761DF4EC050C05AA9994BED181740A475381B1BFC50C01BD2AE99FDA7174024863AB476EF50C0D9C76D56503D1B40', 1450, 1450, 4561, 6.27210000000000001, -67.3281999999999954, 'N 06 16 19', 'O 67 19 41', 183, 93);
INSERT INTO bdc.mux_grid VALUES ('183/94', '0106000020E610000001000000010300000001000000050000001C781ACB19FC50C0EF688975FAA71740529A846E4CC050C03E42A374E71817401665B29FE9CC50C0D189A4D081831340E24248FCB60851C081B08AD1941214401C781ACB19FC50C0EF688975FAA71740', 1451, 1451, 4562, 5.37619999999999987, -67.5254000000000048, 'N 05 22 34', 'O 67 31 31', 183, 94);
INSERT INTO bdc.mux_grid VALUES ('183/95', '0106000020E610000001000000010300000001000000050000003C9A99DCB50851C05B28462192121440A6A9FF8AE7CC50C0EA4C2FD67C8313403009099E7ED950C02EE6AA3B0EDC0F40C6F9A2EF4C1551C0864EEC681C7D10403C9A99DCB50851C05B28462192121440', 1452, 1452, 4563, 4.48029999999999973, -67.7222000000000008, 'N 04 28 49', 'O 67 43 20', 183, 95);
INSERT INTO bdc.mux_grid VALUES ('183/96', '0106000020E610000001000000010300000001000000050000007233D9FF4B1551C08B6C3D2B1A7D1040387780E47CD950C07890F7FA05DC0F402B6C0BEE0EE650C08B993A0400B1084063286409DE2151C02AE2BD5F2ECF09407233D9FF4B1551C08B6C3D2B1A7D1040', 1453, 1453, 4564, 3.58429999999999982, -67.9187000000000012, 'N 03 35 03', 'O 67 55 07', 183, 96);
INSERT INTO bdc.mux_grid VALUES ('183/97', '0106000020E6100000010000000103000000010000000500000000530C49DD2151C09F6C65C72ACF09406A3ED98E0DE650C00E1AC973F9B00840963A11A19BF250C048651597DE8501402C4F445B6B2E51C0D9B7B1EA0FA4024000530C49DD2151C09F6C65C72ACF0940', 1454, 1454, 4566, 2.68829999999999991, -68.1149000000000058, 'N 02 41 17', 'O 68 06 53', 183, 97);
INSERT INTO bdc.mux_grid VALUES ('183/98', '0106000020E61000000100000001030000000100000005000000D68302CA6A2E51C080D2A6330DA4024076858D9B9AF250C0F53FC2B3D9850140EA03ACC625FF50C09212141E5FB5F43F4A0221F5F53A51C0A837DD1DC6F1F63FD68302CA6A2E51C080D2A6330DA40240', 1455, 1455, 4567, 1.79220000000000002, -68.311000000000007, 'N 01 47 31', 'O 68 18 39', 183, 98);
INSERT INTO bdc.mux_grid VALUES ('183/99', '0106000020E61000000100000001030000000100000005000000E805B092F53A51C05306CC6FC2F1F63FEC095A1A25FF50C024BE00AD58B5F43F7A242D6DAE0B51C0803B4E30C47BD93F762083E57E4751C00DAEBD9DB536E13FE805B092F53A51C05306CC6FC2F1F63F', 1456, 1456, 4568, 0.896100000000000008, -68.5069000000000017, 'N 00 53 45', 'O 68 30 24', 183, 99);
INSERT INTO bdc.mux_grid VALUES ('184/100', '0106000020E61000000100000001030000000100000005000000AAD086AB438551C0CC0D24BEB136E13FDC8A8D13734951C0D3AC07B6B77BD93F9019FD9BFB5551C03D59525307DEDFBF5E5FF633CC9151C077EA118D5BECD6BFAAD086AB438551C0CC0D24BEB136E13F', 1457, 1457, 4569, 0, -69.667900000000003, 'N 00 00 00', 'O 69 40 04', 184, 100);
INSERT INTO bdc.mux_grid VALUES ('184/101', '0106000020E6100000010000000103000000010000000500000048B3B02ECC9151C0A775E2565CECD6BFA4C542A1FB5551C04ECE818906DEDFBFBA91D46C846251C0AFFDAB51EE4DF6BF5D7F42FA549E51C0862704C58311F4BF48B3B02ECC9151C0A775E2565CECD6BF', 1458, 1458, 4571, -0.896100000000000008, -69.8636999999999944, 'S 00 53 45', 'O 69 51 49', 184, 101);
INSERT INTO bdc.mux_grid VALUES ('184/102', '0106000020E610000001000000010300000001000000050000007AA58323559E51C0BDBC373A8211F4BF82B7D4CA846251C02D261ACEEA4DF6BFD24930E70E6F51C05A5B579B245202C0CA37DF3FDFAA51C09D266651F03301C07AA58323559E51C0BDBC373A8211F4BF', 1459, 1459, 4572, -1.79220000000000002, -70.0596000000000032, 'S 01 47 31', 'O 70 03 34', 184, 102);
INSERT INTO bdc.mux_grid VALUES ('184/103', '0106000020E6100000010000000103000000010000000500000033C4BA97DFAA51C00CFC01ADEE3301C0549F179E0F6F51C00CA52930215202C0D8318A199C7B51C0D6F73AA7437D09C0B8562D136CB751C0D84E1324115F08C033C4BA97DFAA51C00CFC01ADEE3301C0', 1460, 1460, 4573, -2.68829999999999991, -70.2556000000000012, 'S 02 41 17', 'O 70 15 20', 184, 103);
INSERT INTO bdc.mux_grid VALUES ('184/104', '0106000020E610000001000000010300000001000000050000000A0BCD996CB751C01B62E99F0E5F08C058D0AF299D7B51C050B407913E7D09C020EAB0132D8851C088F04658275410C0D224CE83FCC351C0D88E6FBF1E8A0FC00A0BCD996CB751C01B62E99F0E5F08C0', 1461, 1461, 4575, -3.58429999999999982, -70.4518999999999949, 'S 03 35 03', 'O 70 27 06', 184, 104);
INSERT INTO bdc.mux_grid VALUES ('184/105', '0106000020E61000000100000001030000000100000005000000261B7239FDC351C003274D5A1B8A0FC0FAA6967D2E8851C031E973F6235410C078EB4DE7C29451C018BDD50CA0E913C0A45F29A391D051C06B6788C3895A13C0261B7239FDC351C003274D5A1B8A0FC0', 1462, 1462, 4576, -4.48029999999999973, -70.6483999999999952, 'S 04 28 49', 'O 70 38 54', 184, 105);
INSERT INTO bdc.mux_grid VALUES ('184/106', '0106000020E610000001000000010300000001000000050000007A4C288892D051C0C585AB9F875A13C078DCA0ABC49451C0DA36ABD29BE913C032996DA85EA151C0FEE66221097F17C03409F5842CDD51C0E83563EEF4EF16C07A4C288892D051C0C585AB9F875A13C0', 1463, 1463, 4577, -5.37619999999999987, -70.8452000000000055, 'S 05 22 34', 'O 70 50 42', 184, 106);
INSERT INTO bdc.mux_grid VALUES ('184/107', '0106000020E61000000100000001030000000100000005000000BA94BC992DDD51C00A4D3458F2EF16C0B1C506C860A151C07AA6D90C047F17C0ECCB096E01AE51C0C45CB3C45F141BC0F69ABF3FCEE951C054030E104E851AC0BA94BC992DDD51C00A4D3458F2EF16C0', 1464, 1464, 4578, -6.27210000000000001, -71.0424000000000007, 'S 06 16 19', 'O 71 02 32', 184, 107);
INSERT INTO bdc.mux_grid VALUES ('184/108', '0106000020E6100000010000000103000000010000000500000086D2D484CFE951C0E7C04E064B851AC0FE0BEFE903AE51C089EE58D359141BC0C0689752ACBA51C0DF28F423A1A91EC0462F7DED77F651C03DFBE956921A1EC086D2D484CFE951C0E7C04E064B851AC0', 1465, 1465, 4580, -7.16790000000000038, -71.2399999999999949, 'S 07 10 04', 'O 71 14 24', 184, 108);
INSERT INTO bdc.mux_grid VALUES ('184/109', '0106000020E610000001000000010300000001000000050000000D107D6379F651C046C822D88E1A1EC05A73FC2BAFBA51C01E5BE8529AA91EC07A9C977460C751C034B23835651F21C02C3918AC2A0352C0C6E8D577DFD720C00D107D6379F651C046C822D88E1A1EC0', 1466, 1466, 4582, -8.06359999999999921, -71.4381999999999948, 'S 08 03 49', 'O 71 26 17', 184, 109);
INSERT INTO bdc.mux_grid VALUES ('184/110', '0106000020E61000000100000001030000000100000005000000CE53B8532C0352C09425157DDDD720C05247DFAC63C751C0E6A4315B611F21C0345B2DF71ED451C01E8DA360ECE922C0B067069EE70F52C0CB0D878268A222C0CE53B8532C0352C09425157DDDD720C0', 1467, 1467, 4583, -8.95919999999999916, -71.6370000000000005, 'S 08 57 33', 'O 71 38 13', 184, 110);
INSERT INTO bdc.mux_grid VALUES ('184/111', '0106000020E61000000100000001030000000100000005000000BA9F1578E90F52C051A4714B66A222C08C0DEB8F22D451C04EC93813E8E922C0B2C9B702E9E051C0A98D85A764B424C0E25BE2EAAF1C52C0AB68BEDFE26C24C0BA9F1578E90F52C051A4714B66A222C0', 1468, 1468, 4584, -9.85479999999999912, -71.8363999999999976, 'S 09 51 17', 'O 71 50 11', 184, 111);
INSERT INTO bdc.mux_grid VALUES ('184/112', '0106000020E6100000010000000103000000010000000500000056C349F8B11C52C0B68A3D6BE06C24C07025B1FDECE051C05F6D98E45FB424C01C4172C5BFED51C01A73B79BCC7E26C002DF0AC0842952C071905C224D3726C056C349F8B11C52C0B68A3D6BE06C24C0', 1469, 1469, 4586, -10.7501999999999995, -72.0366000000000071, 'S 10 45 00', 'O 72 02 11', 184, 112);
INSERT INTO bdc.mux_grid VALUES ('184/113', '0106000020E61000000100000001030000000100000005000000E6AECE01872952C0D1F4386F4A3726C0CE04A124C4ED51C0F1F9EA60C77E26C0B8A61A74A4FA51C08D4D6CCD224928C0D0504851673652C06C48BADBA50128C0E6AECE01872952C0D1F4386F4A3726C0', 1470, 1470, 4587, -11.6454000000000004, -72.2376000000000005, 'S 11 38 43', 'O 72 14 15', 184, 113);
INSERT INTO bdc.mux_grid VALUES ('184/114', '0106000020E61000000100000001030000000100000005000000D00289C8693652C0F5D99AE8A20128C086CBAE39A9FA51C046A022181D4928C0A6DC9E4A980752C09EF4F8CA65132AC0EF1379D9584352C04E2E719BEBCB29C0D00289C8693652C0F5D99AE8A20128C0', 1471, 1471, 4588, -12.5404999999999998, -72.4394000000000062, 'S 12 32 25', 'O 72 26 21', 184, 114);
INSERT INTO bdc.mux_grid VALUES ('184/115', '0106000020E610000001000000010300000001000000050000003E9C74875B4352C08D94D966E8CB29C0F8F400799D0752C09E8350985F132AC0901FD28C9C1452C0D5F2952094DD2BC0D6C6459B5A5052C0C5031FEF1C962BC03E9C74875B4352C08D94D966E8CB29C0', 1472, 1472, 4589, -13.4354999999999993, -72.6423000000000059, 'S 13 26 07', 'O 72 38 32', 184, 115);
INSERT INTO bdc.mux_grid VALUES ('184/116', '0106000020E6100000010000000103000000010000000500000094F258815D5052C0B5FF6D7719962BC00EFAA526A21452C08452666D8DDD2BC07A322B87B22152C0EB471B58ACA72DC0002BDEE16D5D52C01CF5226238602DC094F258815D5052C0B5FF6D7719962BC0', 1473, 1473, 4591, -14.3302999999999994, -72.846100000000007, 'S 14 19 49', 'O 72 50 46', 184, 116);
INSERT INTO bdc.mux_grid VALUES ('184/117', '0106000020E6100000010000000103000000010000000500000082258601715D52C0818F90A534602DC0B8C6528FB82152C037B1F120A5A72DC0D24B8C8FDB2E52C08063B5F8AC712FC09CAABF01946A52C0CA41547D3C2A2FC082258601715D52C0818F90A534602DC0', 1474, 1474, 4592, -15.2249999999999996, -73.0511000000000053, 'S 15 13 29', 'O 73 03 03', 184, 117);
INSERT INTO bdc.mux_grid VALUES ('184/118', '0106000020E61000000100000001030000000100000005000000DAAA9B5C976A52C088C9EF79382A2FC0DEF42A09E22E52C018D7D039A5712FC07AC81506193C52C04D544943CA9D30C0767E8659CE7752C087CD58E3137A30C0DAAA9B5C976A52C088C9EF79382A2FC0', 1475, 1475, 4594, -16.1193999999999988, -73.2573000000000008, 'S 16 07 09', 'O 73 15 26', 184, 118);
INSERT INTO bdc.mux_grid VALUES ('184/89', '0106000020E6100000010000000103000000010000000500000046D92CC852FA50C0366D055DDBC824406212E0D08CBE50C0E6E75FB55A812440C4780E4C59CB50C0A2358258E5B62240A83F5B431F0751C0F3BA270066FE224046D92CC852FA50C0366D055DDBC82440', 1476, 1476, 4646, 9.85479999999999912, -67.4993000000000052, 'N 09 51 17', 'O 67 29 57', 184, 89);
INSERT INTO bdc.mux_grid VALUES ('184/90', '0106000020E61000000100000001030000000100000005000000F2842B2A1D0751C0CEA58E7D63FE22402EA2DB5C55CB50C0C323ABA3E0B62240A66BF71916D850C0715CBA225CEC20406A4E47E7DD1351C07BDE9DFCDE332140F2842B2A1D0751C0CEA58E7D63FE2240', 1477, 1477, 4647, 8.95919999999999916, -67.6988000000000056, 'N 08 57 33', 'O 67 41 55', 184, 90);
INSERT INTO bdc.mux_grid VALUES ('184/91', '0106000020E61000000100000001030000000100000005000000A08AA801DC1351C09B29B4B7DC332140AEAEC78C12D850C0E6FD21E357EC2040A24A4BB5C8E450C021304C588B431E4094262C2A922051C08A87700195D21E40A08AA801DC1351C09B29B4B7DC332140', 1478, 1478, 4648, 8.06359999999999921, -67.8974999999999937, 'N 08 03 49', 'O 67 53 51', 184, 91);
INSERT INTO bdc.mux_grid VALUES ('184/92', '0106000020E61000000100000001030000000100000005000000FA382F77902051C0E1C3BFF090D21E4016185F88C5E450C058156ABF83431E403EEF6C4072F150C06D33A3BE46AE1A4024103D2F3D2D51C0F7E1F8EF533D1B40FA382F77902051C0E1C3BFF090D21E40', 1479, 1479, 4650, 7.16790000000000038, -68.0956999999999937, 'N 07 10 04', 'O 68 05 44', 184, 92);
INSERT INTO bdc.mux_grid VALUES ('184/93', '0106000020E61000000100000001030000000100000005000000F2390DAE3B2D51C078C86D56503D1B40F0BB36726FF150C0B79F580840AE1A4072AB34D913FE50C078A9994BED18174074290B15E03951C039D2AE99FDA71740F2390DAE3B2D51C078C86D56503D1B40', 1480, 1480, 4652, 6.27210000000000001, -68.2934000000000054, 'N 06 16 19', 'O 68 17 36', 184, 93);
INSERT INTO bdc.mux_grid VALUES ('184/94', '0106000020E61000000100000001030000000100000005000000F22BEDC4DE3951C01B698975FAA717401E4E576811FE50C05742A374E7181740E4188599AE0A51C0E989A4D081831340B8F61AF67B4651C0AEB08AD194121440F22BEDC4DE3951C01B698975FAA71740', 1481, 1481, 4653, 5.37619999999999987, -68.4906000000000006, 'N 05 22 34', 'O 68 29 26', 184, 94);
INSERT INTO bdc.mux_grid VALUES ('184/95', '0106000020E610000001000000010300000001000000050000000E4E6CD67A4651C07D28462192121440705DD284AC0A51C0FC4C2FD67C831340FABCDB97431751C051E6AA3B0EDC0F4098AD75E9115351C0AA4EEC681C7D10400E4E6CD67A4651C07D28462192121440', 1482, 1482, 4654, 4.48029999999999973, -68.6873999999999967, 'N 04 28 49', 'O 68 41 14', 184, 95);
INSERT INTO bdc.mux_grid VALUES ('184/96', '0106000020E6100000010000000103000000010000000500000040E7ABF9105351C0A76C3D2B1A7D1040082B53DE411751C0B590F7FA05DC0F40F81FDEE7D32351C048993A0400B1084032DC3603A35F51C0E7E1BD5F2ECF094040E7ABF9105351C0A76C3D2B1A7D1040', 1483, 1483, 4656, 3.58429999999999982, -68.883899999999997, 'N 03 35 03', 'O 68 53 01', 184, 96);
INSERT INTO bdc.mux_grid VALUES ('184/97', '0106000020E61000000100000001030000000100000005000000D606DF42A25F51C0776C65C72ACF094036F2AB88D22351C0B919C973F9B0084062EEE39A603051C0F0641597DE85014000031755306C51C0AFB7B1EA0FA40240D606DF42A25F51C0776C65C72ACF0940', 1484, 1484, 4657, 2.68829999999999991, -69.0801000000000016, 'N 02 41 17', 'O 69 04 48', 184, 97);
INSERT INTO bdc.mux_grid VALUES ('184/98', '0106000020E61000000100000001030000000100000005000000A837D5C32F6C51C046D2A6330DA40240463960955F3051C0B23FC2B3D9850140BAB77EC0EA3C51C08912141E5FB5F43F1CB6F3EEBA7851C0B137DD1DC6F1F63FA837D5C32F6C51C046D2A6330DA40240', 1485, 1485, 4658, 1.79220000000000002, -69.2760999999999996, 'N 01 47 31', 'O 69 16 34', 184, 98);
INSERT INTO bdc.mux_grid VALUES ('184/99', '0106000020E61000000100000001030000000100000005000000BAB9828CBA7851C06106CC6FC2F1F63FBABD2C14EA3C51C01FBE00AD58B5F43F4AD8FF66734951C0A93A4E30C47BD93F48D455DF438551C0D8ADBD9DB536E13FBAB9828CBA7851C06106CC6FC2F1F63F', 1486, 1486, 4659, 0.896100000000000008, -69.4719999999999942, 'N 00 53 45', 'O 69 28 19', 184, 99);
INSERT INTO bdc.mux_grid VALUES ('185/100', '0106000020E610000001000000010300000001000000050000007C8459A508C351C0FB0D24BEB136E13FAC3E600D388751C014AD07B6B77BD93F62CDCF95C09351C02F59525307DEDFBF3013C92D91CF51C04CEA118D5BECD6BF7C8459A508C351C0FB0D24BEB136E13F', 1487, 1487, 4661, 0, -70.6329999999999956, 'N 00 00 00', 'O 70 37 58', 185, 100);
INSERT INTO bdc.mux_grid VALUES ('185/101', '0106000020E610000001000000010300000001000000050000001A67832891CF51C07C75E2565CECD6BF7679159BC09351C01ECE818906DEDFBF8C45A76649A051C024FEAB51EE4DF6BF303315F419DC51C0FC2704C58311F4BF1A67832891CF51C07C75E2565CECD6BF', 1488, 1488, 4663, -0.896100000000000008, -70.8289000000000044, 'S 00 53 45', 'O 70 49 43', 185, 101);
INSERT INTO bdc.mux_grid VALUES ('185/102', '0106000020E610000001000000010300000001000000050000004E59561D1ADC51C02BBD373A8211F4BF546BA7C449A051C0B4261ACEEA4DF6BFA4FD02E1D3AC51C0F75A579B245202C09EEBB139A4E851C032266651F03301C04E59561D1ADC51C02BBD373A8211F4BF', 1489, 1489, 4664, -1.79220000000000002, -71.024799999999999, 'S 01 47 31', 'O 71 01 29', 185, 102);
INSERT INTO bdc.mux_grid VALUES ('185/103', '0106000020E6100000010000000103000000010000000500000000788D91A4E851C0B7FB01ADEE3301C02453EA97D4AC51C0A4A42930215202C0AAE55C1361B951C0F7F73AA7437D09C0860A000D31F551C00A4F1324115F08C000788D91A4E851C0B7FB01ADEE3301C0', 1490, 1490, 4666, -2.68829999999999991, -71.220799999999997, 'S 02 41 17', 'O 71 13 14', 185, 103);
INSERT INTO bdc.mux_grid VALUES ('185/104', '0106000020E61000000100000001030000000100000005000000E0BE9F9331F551C02F62E99F0E5F08C02E84822362B951C068B407913E7D09C0F49D830DF2C551C055F04658275410C0A6D8A07DC10152C0708E6FBF1E8A0FC0E0BE9F9331F551C02F62E99F0E5F08C0', 1491, 1491, 4667, -3.58429999999999982, -71.4170000000000016, 'S 03 35 03', 'O 71 25 01', 185, 104);
INSERT INTO bdc.mux_grid VALUES ('185/105', '0106000020E6100000010000000103000000010000000500000000CF4433C20152C08B264D5A1B8A0FC0CC5A6977F3C551C008E973F6235410C04A9F20E187D251C0EEBCD50CA0E913C07E13FC9C560E52C02A6788C3895A13C000CF4433C20152C08B264D5A1B8A0FC0', 1492, 1492, 4668, -4.48029999999999973, -71.6135000000000019, 'S 04 28 49', 'O 71 36 48', 185, 105);
INSERT INTO bdc.mux_grid VALUES ('185/106', '0106000020E610000001000000010300000001000000050000004C00FB81570E52C09885AB9F875A13C04A9073A589D251C0AD36ABD29BE913C0044D40A223DF51C095E66221097F17C006BDC77EF11A52C0803563EEF4EF16C04C00FB81570E52C09885AB9F875A13C0', 1493, 1493, 4669, -5.37619999999999987, -71.810299999999998, 'S 05 22 34', 'O 71 48 37', 185, 106);
INSERT INTO bdc.mux_grid VALUES ('185/107', '0106000020E6100000010000000103000000010000000500000086488F93F21A52C0B34C3458F2EF16C08C79D9C125DF51C0FAA5D90C047F17C0CC7FDC67C6EB51C0085DB3C45F141BC0C44E9239932752C0C1030E104E851AC086488F93F21A52C0B34C3458F2EF16C0', 1494, 1494, 4671, -6.27210000000000001, -72.0074999999999932, 'S 06 16 19', 'O 72 00 27', 185, 107);
INSERT INTO bdc.mux_grid VALUES ('185/108', '0106000020E610000001000000010300000001000000050000006686A77E942752C021C14E064B851AC0C8BFC1E3C8EB51C001EF58D359141BC0861C6A4C71F851C09B28F423A1A91EC026E34FE73C3452C0BAFAE956921A1EC06686A77E942752C021C14E064B851AC0', 1495, 1495, 4672, -7.16790000000000038, -72.2052000000000049, 'S 07 10 04', 'O 72 12 18', 185, 108);
INSERT INTO bdc.mux_grid VALUES ('185/109', '0106000020E61000000100000001030000000100000005000000DEC34F5D3E3452C0EBC722D88E1A1EC02C27CF2574F851C0C35AE8529AA91EC050506A6E250552C0B0B23835651F21C002EDEAA5EF4052C044E9D577DFD720C0DEC34F5D3E3452C0EBC722D88E1A1EC0', 1496, 1496, 4674, -8.06359999999999921, -72.4034000000000049, 'S 08 03 49', 'O 72 24 12', 185, 109);
INSERT INTO bdc.mux_grid VALUES ('185/110', '0106000020E61000000100000001030000000100000005000000A4078B4DF14052C00F26157DDDD720C026FBB1A6280552C063A5315B611F21C0090F00F1E31152C07D8DA360ECE922C0861BD997AC4D52C0290E878268A222C0A4078B4DF14052C00F26157DDDD720C0', 1497, 1497, 4675, -8.95919999999999916, -72.602099999999993, 'S 08 57 33', 'O 72 36 07', 185, 110);
INSERT INTO bdc.mux_grid VALUES ('185/111', '0106000020E610000001000000010300000001000000050000009453E871AE4D52C0A8A4714B66A222C054C1BD89E71152C0B8C93813E8E922C07A7D8AFCAD1E52C0F58D85A764B424C0BA0FB5E4745A52C0E568BEDFE26C24C09453E871AE4D52C0A8A4714B66A222C0', 1498, 1498, 4677, -9.85479999999999912, -72.8015999999999934, 'S 09 51 17', 'O 72 48 05', 185, 111);
INSERT INTO bdc.mux_grid VALUES ('185/112', '0106000020E6100000010000000103000000010000000500000018771CF2765A52C00D8B3D6BE06C24C056D983F7B11E52C08B6D98E45FB424C000F544BF842B52C02973B79BCC7E26C0C492DDB9496752C0AB905C224D3726C018771CF2765A52C00D8B3D6BE06C24C0', 1499, 1499, 4678, -10.7501999999999995, -73.0016999999999996, 'S 10 45 00', 'O 73 00 06', 185, 112);
INSERT INTO bdc.mux_grid VALUES ('185/113', '0106000020E61000000100000001030000000100000005000000B662A1FB4B6752C0F4F4386F4A3726C09EB8731E892B52C015FAEA60C77E26C0885AED6D693852C0934D6CCD224928C0A0041B4B2C7452C07148BADBA50128C0B662A1FB4B6752C0F4F4386F4A3726C0', 1500, 1500, 4679, -11.6454000000000004, -73.202699999999993, 'S 11 38 43', 'O 73 12 09', 185, 113);
INSERT INTO bdc.mux_grid VALUES ('185/114', '0106000020E61000000100000001030000000100000005000000AAB65BC22E7452C0F5D99AE8A20128C0507F81336E3852C05AA022181D4928C06E9071445D4552C092F4F8CA65132AC0C8C74BD31D8152C02D2E719BEBCB29C0AAB65BC22E7452C0F5D99AE8A20128C0', 1501, 1501, 4680, -12.5404999999999998, -73.4046000000000021, 'S 12 32 25', 'O 73 24 16', 185, 114);
INSERT INTO bdc.mux_grid VALUES ('185/115', '0106000020E6100000010000000103000000010000000500000012504781208152C07394D966E8CB29C0CAA8D372624552C0838350985F132AC05ED3A486615252C01EF2952094DD2BC0A47A18951F8E52C00E031FEF1C962BC012504781208152C07394D966E8CB29C0', 1502, 1502, 4682, -13.4354999999999993, -73.6073999999999984, 'S 13 26 07', 'O 73 36 26', 185, 115);
INSERT INTO bdc.mux_grid VALUES ('185/116', '0106000020E6100000010000000103000000010000000500000070A62B7B228E52C0EDFE6D7719962BC0D8AD7820675252C0D051666D8DDD2BC04CE6FD80775F52C01A481B58ACA72DC0E4DEB0DB329B52C037F5226238602DC070A62B7B228E52C0EDFE6D7719962BC0', 1503, 1503, 4683, -14.3302999999999994, -73.8113000000000028, 'S 14 19 49', 'O 73 48 40', 185, 116);
INSERT INTO bdc.mux_grid VALUES ('185/117', '0106000020E6100000010000000103000000010000000500000060D958FB359B52C09F8F90A534602DC0747A25897D5F52C07FB1F120A5A72DC084FF5E89A06C52C0A962B5F8AC712FC0745E92FB58A852C0CA40547D3C2A2FC060D958FB359B52C09F8F90A534602DC0', 1504, 1504, 4684, -15.2249999999999996, -74.0161999999999978, 'S 15 13 29', 'O 74 00 58', 185, 117);
INSERT INTO bdc.mux_grid VALUES ('185/89', '0106000020E610000001000000010300000001000000050000001E8DFFC1173851C0D26C055DDBC8244026C6B2CA51FC50C06FE75FB55A812440842CE1451E0951C0CA358258E5B622407CF32D3DE44451C02DBB270066FE22401E8DFFC1173851C0D26C055DDBC82440', 1505, 1505, 4732, 9.85479999999999912, -68.464500000000001, 'N 09 51 17', 'O 68 27 52', 185, 89);
INSERT INTO bdc.mux_grid VALUES ('185/90', '0106000020E61000000100000001030000000100000005000000CC38FE23E24451C011A68E7D63FE22400656AE561A0951C00724ABA3E0B62240821FCA13DB1551C0515CBA225CEC204047021AE1A25151C05BDE9DFCDE332140CC38FE23E24451C011A68E7D63FE2240', 1506, 1506, 4733, 8.95919999999999916, -68.6638999999999982, 'N 08 57 33', 'O 68 39 50', 185, 90);
INSERT INTO bdc.mux_grid VALUES ('185/91', '0106000020E61000000100000001030000000100000005000000663E7BFBA05151C05F29B4B7DC33214096629A86D71551C0D5FD21E357EC204088FE1DAF8D2251C0C1304C588B431E4056DAFE23575E51C0D587700195D21E40663E7BFBA05151C05F29B4B7DC332140', 1507, 1507, 4735, 8.06359999999999921, -68.8627000000000038, 'N 08 03 49', 'O 68 51 45', 185, 91);
INSERT INTO bdc.mux_grid VALUES ('185/92', '0106000020E61000000100000001030000000100000005000000C8EC0171555E51C047C4BFF090D21E40ECCB31828A2251C0D3156ABF83431E4016A33F3A372F51C02533A3BE46AE1A40F4C30F29026B51C098E1F8EF533D1B40C8EC0171555E51C047C4BFF090D21E40', 1508, 1508, 4736, 7.16790000000000038, -69.0609000000000037, 'N 07 10 04', 'O 69 03 39', 185, 92);
INSERT INTO bdc.mux_grid VALUES ('185/93', '0106000020E61000000100000001030000000100000005000000CCEDDFA7006B51C034C86D56503D1B40C06F096C342F51C05C9F580840AE1A40405F07D3D83B51C0D8A9994BED1817404CDDDD0EA57751C0B0D2AE99FDA71740CCEDDFA7006B51C034C86D56503D1B40', 1509, 1509, 4738, 6.27210000000000001, -69.258499999999998, 'N 06 16 19', 'O 69 15 30', 185, 93);
INSERT INTO bdc.mux_grid VALUES ('185/94', '0106000020E61000000100000001030000000100000005000000BEDFBFBEA37751C076698975FAA71740F4012A62D63B51C0C442A374E7181740BACC5793734851C0128AA4D08183134084AAEDEF408451C0C4B08AD194121440BEDFBFBEA37751C076698975FAA71740', 1510, 1510, 4739, 5.37619999999999987, -69.4556999999999931, 'N 05 22 34', 'O 69 27 20', 185, 94);
INSERT INTO bdc.mux_grid VALUES ('185/95', '0106000020E61000000100000001030000000100000005000000E0013FD03F8451C09E284621921214404011A57E714851C01B4D2FD67C831340CC70AE91085551C004E6AA3B0EDC0F406A6148E3D69051C0864EEC681C7D1040E0013FD03F8451C09E28462192121440', 1511, 1511, 4741, 4.48029999999999973, -69.6525000000000034, 'N 04 28 49', 'O 69 39 09', 185, 95);
INSERT INTO bdc.mux_grid VALUES ('185/96', '0106000020E61000000100000001030000000100000005000000149B7EF3D59051C0876C3D2B1A7D1040D8DE25D8065551C05D90F7FA05DC0F40C6D3B0E1986151C0DD993A0400B10840049009FD679D51C08DE2BD5F2ECF0940149B7EF3D59051C0876C3D2B1A7D1040', 1512, 1512, 4742, 3.58429999999999982, -69.8490000000000038, 'N 03 35 03', 'O 69 50 56', 185, 96);
INSERT INTO bdc.mux_grid VALUES ('185/97', '0106000020E61000000100000001030000000100000005000000A8BAB13C679D51C0256D65C72ACF09400AA67E82976151C0681AC973F9B0084038A2B694256E51C094641597DE850140D6B6E94EF5A951C051B7B1EA0FA40240A8BAB13C679D51C0256D65C72ACF0940', 1513, 1513, 4743, 2.68829999999999991, -70.0451999999999941, 'N 02 41 17', 'O 70 02 42', 185, 97);
INSERT INTO bdc.mux_grid VALUES ('185/98', '0106000020E610000001000000010300000001000000050000007CEBA7BDF4A951C0E7D1A6330DA4024018ED328F246E51C04A3FC2B3D98501408C6B51BAAF7A51C0AB12141E5FB5F43FF069C6E87FB651C0ED37DD1DC6F1F63F7CEBA7BDF4A951C0E7D1A6330DA40240', 1514, 1514, 4744, 1.79220000000000002, -70.2412999999999954, 'N 01 47 31', 'O 70 14 28', 185, 98);
INSERT INTO bdc.mux_grid VALUES ('185/99', '0106000020E610000001000000010300000001000000050000008C6D55867FB651C08F06CC6FC2F1F63F8C71FF0DAF7A51C045BE00AD58B5F43F1C8CD260388751C00E3B4E30C47BD93F1C8828D908C351C01AAEBD9DB536E13F8C6D55867FB651C08F06CC6FC2F1F63F', 1515, 1515, 4746, 0.896100000000000008, -70.4372000000000043, 'N 00 53 45', 'O 70 26 13', 185, 99);
INSERT INTO bdc.mux_grid VALUES ('186/100', '0106000020E610000001000000010300000001000000050000004C382C9FCD0052C0A80D24BEB136E13F80F23207FDC451C0D3AC07B6B77BD93F3481A28F85D151C0A759525307DEDFBF00C79B27560D52C02AEB118D5BECD6BF4C382C9FCD0052C0A80D24BEB136E13F', 1516, 1516, 4747, 0, -71.5982000000000056, 'N 00 00 00', 'O 71 35 53', 186, 100);
INSERT INTO bdc.mux_grid VALUES ('186/101', '0106000020E61000000100000001030000000100000005000000EA1A5622560D52C03676E2565CECD6BF482DE89485D151C0BACE818906DEDFBF5EF979600EDE51C009FEAB51EE4DF6BF00E7E7EDDE1952C0E82704C58311F4BFEA1A5622560D52C03676E2565CECD6BF', 1517, 1517, 4749, -0.896100000000000008, -71.7939999999999969, 'S 00 53 45', 'O 71 47 38', 186, 101);
INSERT INTO bdc.mux_grid VALUES ('186/102', '0106000020E610000001000000010300000001000000050000001A0D2917DF1952C03ABD373A8211F4BF281F7ABE0EDE51C087261ACEEA4DF6BF78B1D5DA98EA51C0445B579B245202C06C9F8433692652C09D266651F03301C01A0D2917DF1952C03ABD373A8211F4BF', 1518, 1518, 4751, -1.79220000000000002, -71.9899000000000058, 'S 01 47 31', 'O 71 59 23', 186, 102);
INSERT INTO bdc.mux_grid VALUES ('186/103', '0106000020E61000000100000001030000000100000005000000D62B608B692652C0F6FB01ADEE3301C0F206BD9199EA51C00CA52930215202C078992F0D26F751C0DBF73AA7437D09C05CBED206F63252C0C54E1324115F08C0D62B608B692652C0F6FB01ADEE3301C0', 1519, 1519, 4752, -2.68829999999999991, -72.1859000000000037, 'S 02 41 17', 'O 72 11 09', 186, 103);
INSERT INTO bdc.mux_grid VALUES ('186/104', '0106000020E61000000100000001030000000100000005000000AA72728DF63252C01762E99F0E5F08C00238551D27F751C023B407913E7D09C0CA515607B70352C02DF04658275410C0728C7377863F52C04E8E6FBF1E8A0FC0AA72728DF63252C01762E99F0E5F08C0', 1520, 1520, 4753, -3.58429999999999982, -72.3821999999999974, 'S 03 35 03', 'O 72 22 55', 186, 104);
INSERT INTO bdc.mux_grid VALUES ('186/105', '0106000020E61000000100000001030000000100000005000000D282172D873F52C047264D5A1B8A0FC0A60E3C71B80352C0D1E873F6235410C02653F3DA4C1052C03ABDD50CA0E913C052C7CE961B4C52C08D6788C3895A13C0D282172D873F52C047264D5A1B8A0FC0', 1521, 1521, 4754, -4.48029999999999973, -72.5786999999999978, 'S 04 28 49', 'O 72 34 43', 186, 105);
INSERT INTO bdc.mux_grid VALUES ('186/106', '0106000020E6100000010000000103000000010000000500000022B4CD7B1C4C52C0F885AB9F875A13C01E44469F4E1052C00E37ABD29BE913C0D800139CE81C52C0B1E66221097F17C0DA709A78B65852C09C3563EEF4EF16C022B4CD7B1C4C52C0F885AB9F875A13C0', 1522, 1522, 4756, -5.37619999999999987, -72.7754999999999939, 'S 05 22 34', 'O 72 46 31', 186, 106);
INSERT INTO bdc.mux_grid VALUES ('186/107', '0106000020E6100000010000000103000000010000000500000050FC618DB75852C0E14C3458F2EF16C0582DACBBEA1C52C027A6D90C047F17C09633AF618B2952C0F15CB3C45F141BC090026533586552C0AA030E104E851AC050FC618DB75852C0E14C3458F2EF16C0', 1523, 1523, 4757, -6.27210000000000001, -72.9727000000000032, 'S 06 16 19', 'O 72 58 21', 186, 107);
INSERT INTO bdc.mux_grid VALUES ('186/108', '0106000020E61000000100000001030000000100000005000000263A7A78596552C02AC14E064B851AC0A87394DD8D2952C0B6EE58D359141BC066D03C46363652C08928F423A1A91EC0E49622E1017252C0FEFAE956921A1EC0263A7A78596552C02AC14E064B851AC0', 1524, 1524, 4758, -7.16790000000000038, -73.1702999999999975, 'S 07 10 04', 'O 73 10 13', 186, 108);
INSERT INTO bdc.mux_grid VALUES ('186/109', '0106000020E61000000100000001030000000100000005000000AF772257037252C004C822D88E1A1EC0FEDAA11F393652C0DA5AE8529AA91EC020043D68EA4252C08FB23835651F21C0D2A0BD9FB47E52C023E9D577DFD720C0AF772257037252C004C822D88E1A1EC0', 1525, 1525, 4760, -8.06359999999999921, -73.3684999999999974, 'S 08 03 49', 'O 73 22 06', 186, 109);
INSERT INTO bdc.mux_grid VALUES ('186/110', '0106000020E6100000010000000103000000010000000500000074BB5D47B67E52C0ED25157DDDD720C0F8AE84A0ED4252C041A5315B611F21C0DAC2D2EAA84F52C0788DA360ECE922C056CFAB91718B52C0260E878268A222C074BB5D47B67E52C0ED25157DDDD720C0', 1526, 1526, 4762, -8.95919999999999916, -73.567300000000003, 'S 08 57 33', 'O 73 34 02', 186, 110);
INSERT INTO bdc.mux_grid VALUES ('186/111', '0106000020E610000001000000010300000001000000050000006E07BB6B738B52C09EA4714B66A222C02C759083AC4F52C0AFC93813E8E922C050315DF6725C52C08A8D85A764B424C093C387DE399852C07968BEDFE26C24C06E07BB6B738B52C09EA4714B66A222C0', 1527, 1527, 4763, -9.85479999999999912, -73.7667000000000002, 'S 09 51 17', 'O 73 46 00', 186, 111);
INSERT INTO bdc.mux_grid VALUES ('186/112', '0106000020E61000000100000001030000000100000005000000E82AEFEB3B9852C0A78A3D6BE06C24C0148D56F1765C52C03B6D98E45FB424C0C0A817B9496952C0F572B79BCC7E26C09446B0B30EA552C062905C224D3726C0E82AEFEB3B9852C0A78A3D6BE06C24C0', 1528, 1528, 4764, -10.7501999999999995, -73.9668999999999954, 'S 10 45 00', 'O 73 58 00', 186, 112);
INSERT INTO bdc.mux_grid VALUES ('186/113', '0106000020E61000000100000001030000000100000005000000861674F510A552C0AEF4386F4A3726C06E6C46184E6952C0CFF9EA60C77E26C05C0EC0672E7652C0EB4D6CCD224928C074B8ED44F1B152C0CB48BADBA50128C0861674F510A552C0AEF4386F4A3726C0', 1529, 1529, 4765, -11.6454000000000004, -74.167900000000003, 'S 11 38 43', 'O 74 10 04', 186, 113);
INSERT INTO bdc.mux_grid VALUES ('186/114', '0106000020E61000000100000001030000000100000005000000746A2EBCF3B152C054DA9AE8A20128C02A33542D337652C0A4A022181D4928C04444443E228352C07AF4F8CA65132AC08E7B1ECDE2BE52C02A2E719BEBCB29C0746A2EBCF3B152C054DA9AE8A20128C0', 1530, 1530, 4767, -12.5404999999999998, -74.3696999999999946, 'S 12 32 25', 'O 74 22 11', 186, 114);
INSERT INTO bdc.mux_grid VALUES ('186/115', '0106000020E61000000100000001030000000100000005000000D4031A7BE5BE52C07994D966E8CB29C09E5CA66C278352C0758350985F132AC034877780269052C0ADF2952094DD2BC06B2EEB8EE4CB52C0B1031FEF1C962BC0D4031A7BE5BE52C07994D966E8CB29C0', 1531, 1531, 4768, -13.4354999999999993, -74.5725999999999942, 'S 13 26 07', 'O 74 34 21', 186, 115);
INSERT INTO bdc.mux_grid VALUES ('186/116', '0106000020E61000000100000001030000000100000005000000245AFE74E7CB52C0A7FF6D7719962BC0BE614B1A2C9052C04D52666D8DDD2BC02E9AD07A3C9D52C035481B58ACA72DC0929283D5F7D852C08EF5226238602DC0245AFE74E7CB52C0A7FF6D7719962BC0', 1532, 1532, 4769, -14.3302999999999994, -74.7763999999999953, 'S 14 19 49', 'O 74 46 35', 186, 116);
INSERT INTO bdc.mux_grid VALUES ('186/117', '0106000020E61000000100000001030000000100000005000000408D2BF5FAD852C0BF8F90A534602DC0522EF882429D52C09FB1F120A5A72DC066B3318365AA52C0E662B5F8AC712FC0521265F51DE652C00641547D3C2A2FC0408D2BF5FAD852C0BF8F90A534602DC0', 1533, 1533, 4770, -15.2249999999999996, -74.9813999999999936, 'S 15 13 29', 'O 74 58 52', 186, 117);
INSERT INTO bdc.mux_grid VALUES ('186/88', '0106000020E6100000010000000103000000010000000500000060C6E8A0056951C02970BAE742932640B229FAAE412D51C0F2DAF8AAC44B26404ED8AE171B3A51C0801BCBE15F812440FE749D09DF7551C0B7B08C1EDEC8244060C6E8A0056951C02970BAE742932640', 1534, 1534, 4814, 10.7501999999999995, -69.2293999999999983, 'N 10 45 00', 'O 69 13 45', 186, 88);
INSERT INTO bdc.mux_grid VALUES ('186/89', '0106000020E61000000100000001030000000100000005000000F240D2BBDC7551C0E16C055DDBC82440FC7985C4163A51C07DE75FB55A81244056E0B33FE34651C03B368258E5B622404EA70037A98251C09EBB270066FE2240F240D2BBDC7551C0E16C055DDBC82440', 1535, 1535, 4815, 9.85479999999999912, -69.4295999999999935, 'N 09 51 17', 'O 69 25 46', 186, 89);
INSERT INTO bdc.mux_grid VALUES ('186/90', '0106000020E6100000010000000103000000010000000500000082ECD01DA78251C05FA68E7D63FE2240DF098150DF4651C07E24ABA3E0B622405ED39C0DA05351C02A5CBA225CEC204000B6ECDA678F51C00BDE9DFCDE33214082ECD01DA78251C05FA68E7D63FE2240', 1536, 1536, 4817, 8.95919999999999916, -69.6290000000000049, 'N 08 57 33', 'O 69 37 44', 186, 90);
INSERT INTO bdc.mux_grid VALUES ('186/91', '0106000020E610000001000000010300000001000000050000003CF24DF5658F51C03329B4B7DC3321405C166D809C5351C093FD21E357EC20404CB2F0A8526051C079304C588B431E402C8ED11D1C9C51C0B787700195D21E403CF24DF5658F51C03329B4B7DC332140', 1537, 1537, 4818, 8.06359999999999921, -69.8277999999999963, 'N 08 03 49', 'O 69 49 40', 186, 91);
INSERT INTO bdc.mux_grid VALUES ('186/92', '0106000020E61000000100000001030000000100000005000000A1A0D46A1A9C51C02CC4BFF090D21E40BA7F047C4F6051C0A3156ABF83431E40E4561234FC6C51C03933A3BE46AE1A40CA77E222C7A851C0C2E1F8EF533D1B40A1A0D46A1A9C51C02CC4BFF090D21E40', 1538, 1538, 4819, 7.16790000000000038, -70.0259999999999962, 'N 07 10 04', 'O 70 01 33', 186, 92);
INSERT INTO bdc.mux_grid VALUES ('186/93', '0106000020E610000001000000010300000001000000050000009CA1B2A1C5A851C04BC86D56503D1B409A23DC65F96C51C08A9F580840AE1A401813DACC9D7951C0CBA9994BED1817401C91B0086AB551C08DD2AE99FDA717409CA1B2A1C5A851C04BC86D56503D1B40', 1539, 1539, 4821, 6.27210000000000001, -70.2236999999999938, 'N 06 16 19', 'O 70 13 25', 186, 93);
INSERT INTO bdc.mux_grid VALUES ('186/94', '0106000020E610000001000000010300000001000000050000008C9392B868B551C04D698975FAA71740C0B5FC5B9B7951C09C42A374E718174086802A8D388651C02F8AA4D081831340505EC0E905C251C0DFB08AD1941214408C9392B868B551C04D698975FAA71740', 1540, 1540, 4823, 5.37619999999999987, -70.4209000000000032, 'N 05 22 34', 'O 70 25 15', 186, 94);
INSERT INTO bdc.mux_grid VALUES ('186/95', '0106000020E61000000100000001030000000100000005000000B2B511CA04C251C0C72846219212144012C57778368651C0444D2FD67C831340A024818BCD9251C0E2E5AA3B0EDC0F403E151BDD9BCE51C0744EEC681C7D1040B2B511CA04C251C0C728462192121440', 1541, 1541, 4824, 4.48029999999999973, -70.6176999999999992, 'N 04 28 49', 'O 70 37 03', 186, 95);
INSERT INTO bdc.mux_grid VALUES ('186/96', '0106000020E61000000100000001030000000100000005000000E44E51ED9ACE51C06B6C3D2B1A7D1040AA92F8D1CB9251C03690F7FA05DC0F409A8783DB5D9F51C0D0993A0400B10840D443DCF62CDB51C070E2BD5F2ECF0940E44E51ED9ACE51C06B6C3D2B1A7D1040', 1542, 1542, 4825, 3.58429999999999982, -70.8141999999999996, 'N 03 35 03', 'O 70 48 50', 186, 96);
INSERT INTO bdc.mux_grid VALUES ('186/97', '0106000020E61000000100000001030000000100000005000000746E84362CDB51C0F46C65C72ACF0940DF59517C5C9F51C0631AC973F9B008400C56898EEAAB51C09B641597DE850140A26ABC48BAE751C02CB7B1EA0FA40240746E84362CDB51C0F46C65C72ACF0940', 1543, 1543, 4826, 2.68829999999999991, -71.0104000000000042, 'N 02 41 17', 'O 71 00 37', 186, 97);
INSERT INTO bdc.mux_grid VALUES ('186/98', '0106000020E610000001000000010300000001000000050000004D9F7AB7B9E751C0DCD1A6330DA40240ECA00589E9AB51C0483FC2B3D98501405E1F24B474B851C0B512141E5FB5F43FC01D99E244F451C0DE37DD1DC6F1F63F4D9F7AB7B9E751C0DCD1A6330DA40240', 1544, 1544, 4828, 1.79220000000000002, -71.2064000000000021, 'N 01 47 31', 'O 71 12 23', 186, 98);
INSERT INTO bdc.mux_grid VALUES ('186/99', '0106000020E610000001000000010300000001000000050000005C21288044F451C06F06CC6FC2F1F63F6025D20774B851C048BE00AD58B5F43FEE3FA55AFDC451C0F13A4E30C47BD93FEA3BFBD2CD0052C0C6ADBD9DB536E13F5C21288044F451C06F06CC6FC2F1F63F', 1545, 1545, 4829, 0.896100000000000008, -71.4022999999999968, 'N 00 53 45', 'O 71 24 08', 186, 99);
INSERT INTO bdc.mux_grid VALUES ('187/100', '0106000020E610000001000000010300000001000000050000001EECFE98923E52C0CC0D24BEB136E13F51A60501C20252C0D3AC07B6B77BD93F043575894A0F52C03D59525307DEDFBFD27A6E211B4B52C077EA118D5BECD6BF1EECFE98923E52C0CC0D24BEB136E13F', 1546, 1546, 4830, 0, -72.5632999999999981, 'N 00 00 00', 'O 72 33 47', 187, 100);
INSERT INTO bdc.mux_grid VALUES ('187/101', '0106000020E61000000100000001030000000100000005000000BCCE281C1B4B52C0A775E2565CECD6BF1AE1BA8E4A0F52C02ACE818906DEDFBF30AD4C5AD31B52C000FEAB51EE4DF6BFD29ABAE7A35752C0E82704C58311F4BFBCCE281C1B4B52C0A775E2565CECD6BF', 1547, 1547, 4833, -0.896100000000000008, -72.759200000000007, 'S 00 53 45', 'O 72 45 32', 187, 101);
INSERT INTO bdc.mux_grid VALUES ('187/102', '0106000020E61000000100000001030000000100000005000000F0C0FB10A45752C00DBD373A8211F4BFF4D24CB8D31B52C099261ACEEA4DF6BF4465A8D45D2852C00E5B579B245202C04053572D2E6452C048266651F03301C0F0C0FB10A45752C00DBD373A8211F4BF', 1548, 1548, 4834, -1.79220000000000002, -72.9551000000000016, 'S 01 47 31', 'O 72 57 18', 187, 102);
INSERT INTO bdc.mux_grid VALUES ('187/103', '0106000020E61000000100000001030000000100000005000000A8DF32852E6452C0AEFB01ADEE3301C0C8BA8F8B5E2852C0AEA42930215202C04E4D0207EB3452C0FAF73AA7437D09C02E72A500BB7052C0FB4E1324115F08C0A8DF32852E6452C0AEFB01ADEE3301C0', 1549, 1549, 4835, -2.68829999999999991, -73.1510999999999996, 'S 02 41 17', 'O 73 09 03', 187, 103);
INSERT INTO bdc.mux_grid VALUES ('187/104', '0106000020E610000001000000010300000001000000050000007E264587BB7052C05162E99F0E5F08C0CEEB2717EC3452C074B407913E7D09C0960529017C4152C099F04658275410C0444046714B7D52C00E8F6FBF1E8A0FC07E264587BB7052C05162E99F0E5F08C0', 1550, 1550, 4836, -3.58429999999999982, -73.3473000000000042, 'S 03 35 03', 'O 73 20 50', 187, 104);
INSERT INTO bdc.mux_grid VALUES ('187/105', '0106000020E610000001000000010300000001000000050000009E36EA264C7D52C027274D5A1B8A0FC07AC20E6B7D4152C02FE973F6235410C0FA06C6D4114E52C096BDD50CA0E913C01C7BA190E08952C0FC6788C3895A13C09E36EA264C7D52C027274D5A1B8A0FC0', 1551, 1551, 4837, -4.48029999999999973, -73.5438000000000045, 'S 04 28 49', 'O 73 32 37', 187, 105);
INSERT INTO bdc.mux_grid VALUES ('187/106', '0106000020E61000000100000001030000000100000005000000EE67A075E18952C06686AB9F875A13C0F4F71899134E52C06837ABD29BE913C0ACB4E595AD5A52C00BE76221097F17C0A6246D727B9652C00A3663EEF4EF16C0EE67A075E18952C06686AB9F875A13C0', 1552, 1552, 4838, -5.37619999999999987, -73.7406000000000006, 'S 05 22 34', 'O 73 44 26', 187, 106);
INSERT INTO bdc.mux_grid VALUES ('187/107', '0106000020E6100000010000000103000000010000000500000026B034877C9652C0394D3458F2EF16C026E17EB5AF5A52C092A6D90C047F17C062E7815B506752C0DB5CB3C45F141BC062B6372D1DA352C081030E104E851AC026B034877C9652C0394D3458F2EF16C0', 1553, 1553, 4839, -6.27210000000000001, -73.9377999999999957, 'S 06 16 19', 'O 73 56 16', 187, 107);
INSERT INTO bdc.mux_grid VALUES ('187/108', '0106000020E6100000010000000103000000010000000500000006EE4C721EA352C0E3C04E064B851AC0662767D7526752C0C3EE58D359141BC024840F40FB7352C01628F423A1A91EC0C24AF5DAC6AF52C038FAE956921A1EC006EE4C721EA352C0E3C04E064B851AC0', 1554, 1554, 4840, -7.16790000000000038, -74.1354999999999933, 'S 07 10 04', 'O 74 08 07', 187, 108);
INSERT INTO bdc.mux_grid VALUES ('187/109', '0106000020E61000000100000001030000000100000005000000802BF550C8AF52C05DC722D88E1A1EC0CC8E7419FE7352C0335AE8529AA91EC0F0B70F62AF8052C03EB23835651F21C0A254909979BC52C0D2E8D577DFD720C0802BF550C8AF52C05DC722D88E1A1EC0', 1555, 1555, 4843, -8.06359999999999921, -74.3336999999999932, 'S 08 03 49', 'O 74 20 01', 187, 109);
INSERT INTO bdc.mux_grid VALUES ('187/110', '0106000020E61000000100000001030000000100000005000000326F30417BBC52C0B125157DDDD720C0C662579AB28052C0EFA4315B611F21C0AC76A5E46D8D52C0A68DA360ECE922C018837E8B36C952C0680E878268A222C0326F30417BBC52C0B125157DDDD720C0', 1556, 1556, 4844, -8.95919999999999916, -74.5323999999999955, 'S 08 57 33', 'O 74 31 56', 187, 110);
INSERT INTO bdc.mux_grid VALUES ('187/111', '0106000020E6100000010000000103000000010000000500000046BB8D6538C952C0C3A4714B66A222C00629637D718D52C0D4C93813E8E922C02AE52FF0379A52C0AF8D85A764B424C06A775AD8FED552C09E68BEDFE26C24C046BB8D6538C952C0C3A4714B66A222C0', 1557, 1557, 4845, -9.85479999999999912, -74.731899999999996, 'S 09 51 17', 'O 74 43 54', 187, 111);
INSERT INTO bdc.mux_grid VALUES ('187/112', '0106000020E61000000100000001030000000100000005000000CCDEC1E500D652C0BF8A3D6BE06C24C0E84029EB3B9A52C0686D98E45FB424C0925CEAB20EA752C02373B79BCC7E26C078FA82ADD3E252C07A905C224D3726C0CCDEC1E500D652C0BF8A3D6BE06C24C0', 1558, 1558, 4846, -10.7501999999999995, -74.9320000000000022, 'S 10 45 00', 'O 74 55 55', 187, 112);
INSERT INTO bdc.mux_grid VALUES ('187/113', '0106000020E6100000010000000103000000010000000500000058CA46EFD5E252C0DCF4386F4A3726C04020191213A752C0FEF9EA60C77E26C02BC29261F3B352C09C4D6CCD224928C0426CC03EB6EF52C07848BADBA50128C058CA46EFD5E252C0DCF4386F4A3726C0', 1559, 1559, 4847, -11.6454000000000004, -75.1329999999999956, 'S 11 38 43', 'O 75 07 58', 187, 113);
INSERT INTO bdc.mux_grid VALUES ('187/114', '0106000020E61000000100000001030000000100000005000000481E01B6B8EF52C0F9D99AE8A20128C0F0E62627F8B352C05EA022181D4928C00CF81638E7C052C035F4F8CA65132AC0642FF1C6A7FC52C0D02D719BEBCB29C0481E01B6B8EF52C0F9D99AE8A20128C0', 1560, 1560, 4848, -12.5404999999999998, -75.3349000000000046, 'S 12 32 25', 'O 75 20 05', 187, 114);
INSERT INTO bdc.mux_grid VALUES ('187/115', '0106000020E61000000100000001030000000100000005000000B6B7EC74AAFC52C01094D966E8CB29C05E107966ECC052C0348350985F132AC0F23A4A7AEBCD52C0ECF1952094DD2BC048E2BD88A90953C0C9021FEF1C962BC0B6B7EC74AAFC52C01094D966E8CB29C0', 1561, 1561, 4849, -13.4354999999999993, -75.537700000000001, 'S 13 26 07', 'O 75 32 15', 187, 115);
INSERT INTO bdc.mux_grid VALUES ('187/88', '0106000020E61000000100000001030000000100000005000000287ABB9ACAA651C07170BAE74293264078DDCCA8066B51C03ADBF8AAC44B2640168C8111E07751C0C81BCBE15F812440C7287003A4B351C0FFB08C1EDEC82440287ABB9ACAA651C07170BAE742932640', 1562, 1562, 4888, 10.7501999999999995, -70.1945999999999941, 'N 10 45 00', 'O 70 11 40', 187, 88);
INSERT INTO bdc.mux_grid VALUES ('187/89', '0106000020E61000000100000001030000000100000005000000B2F4A4B5A1B351C0226D055DDBC82440CE2D58BEDB7751C0D1E75FB55A8124402C948639A88451C00F368258E5B62240125BD3306EC051C060BB270066FE2240B2F4A4B5A1B351C0226D055DDBC82440', 1563, 1563, 4890, 9.85479999999999912, -70.3948000000000036, 'N 09 51 17', 'O 70 23 41', 187, 89);
INSERT INTO bdc.mux_grid VALUES ('187/90', '0106000020E610000001000000010300000001000000050000005CA0A3176CC051C03DA68E7D63FE224098BD534AA48451C03124ABA3E0B6224016876F07659151C0DE5BBA225CEC2040DC69BFD42CCD51C0E9DD9DFCDE3321405CA0A3176CC051C03DA68E7D63FE2240', 1564, 1564, 4891, 8.95919999999999916, -70.5942000000000007, 'N 08 57 33', 'O 70 35 39', 187, 90);
INSERT INTO bdc.mux_grid VALUES ('187/91', '0106000020E6100000010000000103000000010000000500000000A620EF2ACD51C0F428B4B7DC33214032CA3F7A619151C06AFD21E357EC20401E66C3A2179E51C023314C588B431E40EE41A417E1D951C03788700195D21E4000A620EF2ACD51C0F428B4B7DC332140', 1565, 1565, 4892, 8.06359999999999921, -70.7930000000000064, 'N 08 03 49', 'O 70 47 34', 187, 91);
INSERT INTO bdc.mux_grid VALUES ('187/92', '0106000020E610000001000000010300000001000000050000006254A764DFD951C0B0C4BFF090D21E408E33D775149E51C054166ABF83431E40BC0AE52DC1AA51C0E932A3BE46AE1A40912BB51C8CE651C046E1F8EF533D1B406254A764DFD951C0B0C4BFF090D21E40', 1566, 1566, 4893, 7.16790000000000038, -70.9912000000000063, 'N 07 10 04', 'O 70 59 28', 187, 92);
INSERT INTO bdc.mux_grid VALUES ('187/93', '0106000020E610000001000000010300000001000000050000006455859B8AE651C0D5C76D56503D1B406AD7AE5FBEAA51C0279F580840AE1A40E8C6ACC662B751C0EBA9994BED181740E24483022FF351C097D2AE99FDA717406455859B8AE651C0D5C76D56503D1B40', 1567, 1567, 4896, 6.27210000000000001, -71.1888000000000005, 'N 06 16 19', 'O 71 11 19', 187, 93);
INSERT INTO bdc.mux_grid VALUES ('187/94', '0106000020E61000000100000001030000000100000005000000594765B22DF351C065698975FAA717408F69CF5560B751C0B542A374E71817405434FD86FDC351C0C689A4D081831340201293E3CAFF51C077B08AD194121440594765B22DF351C065698975FAA71740', 1568, 1568, 4897, 5.37619999999999987, -71.3859999999999957, 'N 05 22 34', 'O 71 23 09', 187, 94);
INSERT INTO bdc.mux_grid VALUES ('187/95', '0106000020E610000001000000010300000001000000050000008669E4C3C9FF51C06C28462192121440E8784A72FBC351C0EA4C2FD67C83134072D8538592D051C02EE6AA3B0EDC0F4010C9EDD6600C52C0984EEC681C7D10408669E4C3C9FF51C06C28462192121440', 1569, 1569, 4898, 4.48029999999999973, -71.582800000000006, 'N 04 28 49', 'O 71 34 58', 187, 95);
INSERT INTO bdc.mux_grid VALUES ('187/96', '0106000020E61000000100000001030000000100000005000000B20224E75F0C52C0876C3D2B1A7D10407A46CBCB90D051C07390F7FA05DC0F406A3B56D522DD51C08D993A0400B10840A4F7AEF0F11852C02CE2BD5F2ECF0940B20224E75F0C52C0876C3D2B1A7D1040', 1570, 1570, 4899, 3.58429999999999982, -71.7793000000000063, 'N 03 35 03', 'O 71 46 45', 187, 96);
INSERT INTO bdc.mux_grid VALUES ('187/97', '0106000020E6100000010000000103000000010000000500000046225730F11852C0B66C65C72ACF0940AC0D247621DD51C00E1AC973F9B00840D8095C88AFE951C046641597DE850140721E8F427F2552C0EEB6B1EA0FA4024046225730F11852C0B66C65C72ACF0940', 1571, 1571, 4901, 2.68829999999999991, -71.9754999999999967, 'N 02 41 17', 'O 71 58 31', 187, 97);
INSERT INTO bdc.mux_grid VALUES ('187/98', '0106000020E610000001000000010300000001000000050000001E534DB17E2552C0A3D1A6330DA40240BC54D882AEE951C00E3FC2B3D985014030D3F6AD39F651C0C712141E5FB5F43F92D16BDC093252C0F037DD1DC6F1F63F1E534DB17E2552C0A3D1A6330DA40240', 1572, 1572, 4902, 1.79220000000000002, -72.171599999999998, 'N 01 47 31', 'O 72 10 17', 187, 98);
INSERT INTO bdc.mux_grid VALUES ('187/99', '0106000020E610000001000000010300000001000000050000002CD5FA79093252C07706CC6FC2F1F63F2ED9A40139F651C03FBE00AD58B5F43FBCF37754C20252C0A93A4E30C47BD93FBAEFCDCC923E52C0C6ADBD9DB536E13F2CD5FA79093252C07706CC6FC2F1F63F', 1573, 1573, 4903, 0.896100000000000008, -72.3675000000000068, 'N 00 53 45', 'O 72 22 02', 187, 99);
INSERT INTO bdc.mux_grid VALUES ('188/100', '0106000020E61000000100000001030000000100000005000000F29FD192577C52C0E90D24BEB136E13F225AD8FA864052C0CCAC07B6B77BD93FD6E847830F4D52C07659525307DEDFBFA62E411BE08852C070EA118D5BECD6BFF29FD192577C52C0E90D24BEB136E13F', 1574, 1574, 4904, 0, -73.528499999999994, 'N 00 00 00', 'O 73 31 42', 188, 100);
INSERT INTO bdc.mux_grid VALUES ('188/101', '0106000020E610000001000000010300000001000000050000008C82FB15E08852C0E775E2565CECD6BFEA948D880F4D52C065CE818906DEDFBFFE601F54985952C012FEAB51EE4DF6BFA24E8DE1689552C0F32704C58311F4BF8C82FB15E08852C0E775E2565CECD6BF', 1575, 1575, 4907, -0.896100000000000008, -73.7242999999999995, 'S 00 53 45', 'O 73 43 27', 188, 101);
INSERT INTO bdc.mux_grid VALUES ('188/102', '0106000020E61000000100000001030000000100000005000000C274CE0A699552C02BBD373A8211F4BFC9861FB2985952C09A261ACEEA4DF6BF18197BCE226652C0EE5A579B245202C012072A27F3A152C032266651F03301C0C274CE0A699552C02BBD373A8211F4BF', 1576, 1576, 4908, -1.79220000000000002, -73.9201999999999941, 'S 01 47 31', 'O 73 55 12', 188, 102);
INSERT INTO bdc.mux_grid VALUES ('188/103', '0106000020E610000001000000010300000001000000050000007793057FF3A152C0A9FB01ADEE3301C09A6E6285236652C096A42930215202C02001D500B07252C0EEF73AA7437D09C0FD2578FA7FAE52C0014F1324115F08C07793057FF3A152C0A9FB01ADEE3301C0', 1577, 1577, 4909, -2.68829999999999991, -74.1162000000000063, 'S 02 41 17', 'O 74 06 58', 188, 103);
INSERT INTO bdc.mux_grid VALUES ('188/104', '0106000020E610000001000000010300000001000000050000004EDA178180AE52C04162E99F0E5F08C0A09FFA10B17252C063B407913E7D09C06AB9FBFA407F52C0D4F04658275410C016F4186B10BB52C0868F6FBF1E8A0FC04EDA178180AE52C04162E99F0E5F08C0', 1578, 1578, 4910, -3.58429999999999982, -74.3125, 'S 03 35 03', 'O 74 18 44', 188, 104);
INSERT INTO bdc.mux_grid VALUES ('188/105', '0106000020E6100000010000000103000000010000000500000070EABC2011BB52C09B274D5A1B8A0FC04476E164427F52C07DE973F6235410C0C2BA98CED68B52C062BDD50CA0E913C0EE2E748AA5C752C0B36788C3895A13C070EABC2011BB52C09B274D5A1B8A0FC0', 1579, 1579, 4912, -4.48029999999999973, -74.5090000000000003, 'S 04 28 49', 'O 74 30 32', 188, 105);
INSERT INTO bdc.mux_grid VALUES ('188/106', '0106000020E61000000100000001030000000100000005000000C01B736FA6C752C01A86AB9F875A13C0BEABEB92D88B52C03137ABD29BE913C07868B88F729852C019E76221097F17C07AD83F6C40D452C0023663EEF4EF16C0C01B736FA6C752C01A86AB9F875A13C0', 1580, 1580, 4913, -5.37619999999999987, -74.7057999999999964, 'S 05 22 34', 'O 74 42 20', 188, 106);
INSERT INTO bdc.mux_grid VALUES ('188/107', '0106000020E61000000100000001030000000100000005000000FC63078141D452C02E4D3458F2EF16C0FA9451AF749852C089A6D90C047F17C0389B545515A552C0195DB3C45F141BC03A6A0A27E2E052C0BC030E104E851AC0FC63078141D452C02E4D3458F2EF16C0', 1581, 1581, 4914, -6.27210000000000001, -74.9030000000000058, 'S 06 16 19', 'O 74 54 10', 188, 107);
INSERT INTO bdc.mux_grid VALUES ('188/108', '0106000020E61000000100000001030000000100000005000000CEA11F6CE3E052C03CC14E064B851AC048DB39D117A552C0DFEE58D359141BC00638E239C0B152C07728F423A1A91EC08CFEC7D48BED52C0D5FAE956921A1EC0CEA11F6CE3E052C03CC14E064B851AC0', 1582, 1582, 4915, -7.16790000000000038, -75.1006, 'S 07 10 04', 'O 75 06 02', 188, 108);
INSERT INTO bdc.mux_grid VALUES ('188/109', '0106000020E6100000010000000103000000010000000500000052DFC74A8DED52C0E7C722D88E1A1EC0A0424713C3B152C0BD5AE8529AA91EC0C46BE25B74BE52C0ACB23835651F21C0760863933EFA52C041E9D577DFD720C052DFC74A8DED52C0E7C722D88E1A1EC0', 1583, 1583, 4918, -8.06359999999999921, -75.2988, 'S 08 03 49', 'O 75 17 55', 188, 109);
INSERT INTO bdc.mux_grid VALUES ('188/110', '0106000020E610000001000000010300000001000000050000001823033B40FA52C00D26157DDDD720C08A162A9477BE52C075A5315B611F21C06C2A78DE32CB52C08E8DA360ECE922C0FA365185FB0653C0270E878268A222C01823033B40FA52C00D26157DDDD720C0', 1584, 1584, 4919, -8.95919999999999916, -75.4976000000000056, 'S 08 57 33', 'O 75 29 51', 188, 110);
INSERT INTO bdc.mux_grid VALUES ('188/111', '0106000020E610000001000000010300000001000000050000000C6F605FFD0653C0A1A4714B66A222C0DCDC357736CB52C09DC93813E8E922C0009902EAFCD752C05D8D85A764B424C0302B2DD2C31353C06068BEDFE26C24C00C6F605FFD0653C0A1A4714B66A222C0', 1585, 1585, 4920, -9.85479999999999912, -75.6970000000000027, 'S 09 51 17', 'O 75 41 49', 188, 111);
INSERT INTO bdc.mux_grid VALUES ('188/112', '0106000020E610000001000000010300000001000000050000008C9294DFC51353C0888A3D6BE06C24C0C8F4FBE400D852C0086D98E45FB424C07810BDACD3E452C02473B79BCC7E26C03AAE55A7982053C0A5905C224D3726C08C9294DFC51353C0888A3D6BE06C24C0', 1586, 1586, 4921, -10.7501999999999995, -75.897199999999998, 'S 10 45 00', 'O 75 53 49', 188, 112);
INSERT INTO bdc.mux_grid VALUES ('188/113', '0106000020E61000000100000001030000000100000005000000287E19E99A2053C0F5F4386F4A3726C010D4EB0BD8E452C016FAEA60C77E26C0FA75655BB8F152C0934D6CCD224928C0122093387B2D53C07248BADBA50128C0287E19E99A2053C0F5F4386F4A3726C0', 1587, 1587, 4923, -11.6454000000000004, -76.0982000000000056, 'S 11 38 43', 'O 76 05 53', 188, 113);
INSERT INTO bdc.mux_grid VALUES ('188/114', '0106000020E6100000010000000103000000010000000500000012D2D3AF7D2D53C0FFD99AE8A20128C0CA9AF920BDF152C050A022181D4928C0E4ABE931ACFE52C00BF4F8CA65132AC02CE3C3C06C3A53C0BA2D719BEBCB29C012D2D3AF7D2D53C0FFD99AE8A20128C0', 1588, 1588, 4924, -12.5404999999999998, -76.2999999999999972, 'S 12 32 25', 'O 76 18 00', 188, 114);
INSERT INTO bdc.mux_grid VALUES ('188/89', '0106000020E610000001000000010300000001000000050000009AA877AF66F151C0DF6C055DDBC8244092E12AB8A0B551C067E75FB55A812440F04759336DC251C0C2358258E5B62240F80EA62A33FE51C03ABB270066FE22409AA877AF66F151C0DF6C055DDBC82440', 1589, 1589, 4962, 9.85479999999999912, -71.3598999999999961, 'N 09 51 17', 'O 71 21 35', 188, 89);
INSERT INTO bdc.mux_grid VALUES ('188/91', '0106000020E61000000100000001030000000100000005000000E559F3E8EF0A52C06E29B4B7DC332140F47D127426CF51C0BAFD21E357EC2040E419969CDCDB51C08B304C588B431E40D6F57611A61752C0F387700195D21E40E559F3E8EF0A52C06E29B4B7DC332140', 1590, 1590, 4964, 8.06359999999999921, -71.7580999999999989, 'N 08 03 49', 'O 71 45 29', 188, 91);
INSERT INTO bdc.mux_grid VALUES ('188/92', '0106000020E6100000010000000103000000010000000500000044087A5EA41752C05CC4BFF090D21E4056E7A96FD9DB51C0C1156ABF83431E4082BEB72786E851C01333A3BE46AE1A4070DF8716512452C0AEE1F8EF533D1B4044087A5EA41752C05CC4BFF090D21E40', 1591, 1591, 4965, 7.16790000000000038, -71.9562999999999988, 'N 07 10 04', 'O 71 57 22', 188, 92);
INSERT INTO bdc.mux_grid VALUES ('188/93', '0106000020E610000001000000010300000001000000050000003D0958954F2452C02BC86D56503D1B40328B815983E851C0539F580840AE1A40B07A7FC027F551C0D1A9994BED181740BCF855FCF33052C0A8D2AE99FDA717403D0958954F2452C02BC86D56503D1B40', 1592, 1592, 4968, 6.27210000000000001, -72.1539999999999964, 'N 06 16 19', 'O 72 09 14', 188, 93);
INSERT INTO bdc.mux_grid VALUES ('188/94', '0106000020E610000001000000010300000001000000050000002EFB37ACF23052C071698975FAA717405C1DA24F25F551C0AB42A374E718174024E8CF80C20152C07889A4D081831340F6C565DD8F3D52C03FB08AD1941214402EFB37ACF23052C071698975FAA71740', 1593, 1593, 4969, 5.37619999999999987, -72.3512000000000057, 'N 05 22 34', 'O 72 21 04', 188, 94);
INSERT INTO bdc.mux_grid VALUES ('188/95', '0106000020E61000000100000001030000000100000005000000501DB7BD8E3D52C01428462192121440BA2C1D6CC00152C0A54C2FD67C831340428C267F570E52C01EE7AA3B0EDC0F40D87CC0D0254A52C0FE4EEC681C7D1040501DB7BD8E3D52C01428462192121440', 1594, 1594, 4970, 4.48029999999999973, -72.5480000000000018, 'N 04 28 49', 'O 72 32 52', 188, 95);
INSERT INTO bdc.mux_grid VALUES ('188/96', '0106000020E610000001000000010300000001000000050000008EB6F6E0244A52C0186D3D2B1A7D104046FA9DC5550E52C05891F7FA05DC0F4038EF28CFE71A52C0D9993A0400B108407EAB81EAB65652C0B1E2BD5F2ECF09408EB6F6E0244A52C0186D3D2B1A7D1040', 1595, 1595, 4972, 3.58429999999999982, -72.7443999999999988, 'N 03 35 03', 'O 72 44 40', 188, 96);
INSERT INTO bdc.mux_grid VALUES ('188/97', '0106000020E6100000010000000103000000010000000500000018D6292AB65652C0196D65C72ACF09407AC1F66FE61A52C0611AC973F9B00840A6BD2E82742752C00F651597DE85014044D2613C446352C0C8B7B1EA0FA4024018D6292AB65652C0196D65C72ACF0940', 1596, 1596, 4973, 2.68829999999999991, -72.9407000000000068, 'N 02 41 17', 'O 72 56 26', 188, 97);
INSERT INTO bdc.mux_grid VALUES ('188/98', '0106000020E61000000100000001030000000100000005000000EA0620AB436352C059D2A6330DA402408E08AB7C732752C0DC3FC2B3D98501400287C9A7FE3352C0DC12141E5FB5F43F61853ED6CE6F52C0D737DD1DC6F1F63FEA0620AB436352C059D2A6330DA40240', 1597, 1597, 4974, 1.79220000000000002, -73.1367000000000047, 'N 01 47 31', 'O 73 08 12', 188, 98);
INSERT INTO bdc.mux_grid VALUES ('188/99', '0106000020E61000000100000001030000000100000005000000FE88CD73CE6F52C09C06CC6FC2F1F63F008D77FBFD3352C04ABE00AD58B5F43F8EA74A4E874052C0A23A4E30C47BD93F8EA3A0C6577C52C0F6ADBD9DB536E13FFE88CD73CE6F52C09C06CC6FC2F1F63F', 1598, 1598, 4975, 0.896100000000000008, -73.3325999999999993, 'N 00 53 45', 'O 73 19 57', 188, 99);
INSERT INTO bdc.mux_grid VALUES ('189/100', '0106000020E61000000100000001030000000100000005000000C053A48C1CBA52C0F00D24BEB136E13FF40DABF44B7E52C063AD07B6B77BD93FA89C1A7DD48A52C08858525307DEDFBF74E21315A5C652C00CEA118D5BECD6BFC053A48C1CBA52C0F00D24BEB136E13F', 1599, 1599, 4976, 0, -74.4936000000000007, 'N 00 00 00', 'O 74 29 36', 189, 100);
INSERT INTO bdc.mux_grid VALUES ('189/101', '0106000020E610000001000000010300000001000000050000005C36CE0FA5C652C08375E2565CECD6BFBC486082D48A52C0BFCD818906DEDFBFD014F24D5D9752C0EEFDAB51EE4DF6BF720260DB2DD352C0DF2704C58311F4BF5C36CE0FA5C652C08375E2565CECD6BF', 1600, 1600, 4978, -0.896100000000000008, -74.6894000000000062, 'S 00 53 45', 'O 74 41 22', 189, 101);
INSERT INTO bdc.mux_grid VALUES ('189/102', '0106000020E610000001000000010300000001000000050000009228A1042ED352C0FCBC373A8211F4BF9A3AF2AB5D9752C06C261ACEEA4DF6BFEACC4DC8E7A352C0F75A579B245202C0E2BAFC20B8DF52C03B266651F03301C09228A1042ED352C0FCBC373A8211F4BF', 1601, 1601, 4979, -1.79220000000000002, -74.8854000000000042, 'S 01 47 31', 'O 74 53 07', 189, 102);
INSERT INTO bdc.mux_grid VALUES ('189/103', '0106000020E610000001000000010300000001000000050000004C47D878B8DF52C0A1FB01ADEE3301C06722357FE8A352C0B7A42930215202C0EDB4A7FA74B052C003F83AA7437D09C0D2D94AF444EC52C0ED4E1324115F08C04C47D878B8DF52C0A1FB01ADEE3301C0', 1602, 1602, 4980, -2.68829999999999991, -75.0814000000000021, 'S 02 41 17', 'O 75 04 52', 189, 103);
INSERT INTO bdc.mux_grid VALUES ('189/104', '0106000020E61000000100000001030000000100000005000000248EEA7A45EC52C03262E99F0E5F08C07253CD0A76B052C06BB407913E7D09C03A6DCEF405BD52C0D5F04658275410C0ECA7EB64D5F852C0708F6FBF1E8A0FC0248EEA7A45EC52C03262E99F0E5F08C0', 1603, 1603, 4982, -3.58429999999999982, -75.2776000000000067, 'S 03 35 03', 'O 75 16 39', 189, 104);
INSERT INTO bdc.mux_grid VALUES ('189/105', '0106000020E61000000100000001030000000100000005000000449E8F1AD6F852C08E274D5A1B8A0FC0182AB45E07BD52C077E973F6235410C0946E6BC89BC952C060BDD50CA0E913C0C0E246846A0553C0B36788C3895A13C0449E8F1AD6F852C08E274D5A1B8A0FC0', 1604, 1604, 4983, -4.48029999999999973, -75.4741000000000071, 'S 04 28 49', 'O 75 28 26', 189, 105);
INSERT INTO bdc.mux_grid VALUES ('189/106', '0106000020E6100000010000000103000000010000000500000094CF45696B0553C01A86AB9F875A13C0915FBE8C9DC952C02F37ABD29BE913C04A1C8B8937D652C053E76221097F17C04C8C1266051253C03D3663EEF4EF16C094CF45696B0553C01A86AB9F875A13C0', 1605, 1605, 4984, -5.37619999999999987, -75.6709000000000032, 'S 05 22 34', 'O 75 40 15', 189, 106);
INSERT INTO bdc.mux_grid VALUES ('189/107', '0106000020E61000000100000001030000000100000005000000D017DA7A061253C0644D3458F2EF16C0D04824A939D652C0BFA6D90C047F17C0094F274FDAE252C0085CB3C45F141BC0081EDD20A71E53C0AE020E104E851AC0D017DA7A061253C0644D3458F2EF16C0', 1606, 1606, 4985, -6.27210000000000001, -75.8680999999999983, 'S 06 16 19', 'O 75 52 05', 189, 107);
INSERT INTO bdc.mux_grid VALUES ('189/108', '0106000020E61000000100000001030000000100000005000000A255F265A81E53C025C04E064B851AC00C8F0CCBDCE252C0F1ED58D359141BC0CAEBB43385EF52C0C427F423A1A91EC062B29ACE502B53C0F9F9E956921A1EC0A255F265A81E53C025C04E064B851AC0', 1607, 1607, 4987, -7.16790000000000038, -76.0657999999999959, 'S 07 10 04', 'O 76 03 56', 189, 108);
INSERT INTO bdc.mux_grid VALUES ('189/109', '0106000020E6100000010000000103000000010000000500000020939A44522B53C01BC722D88E1A1EC070F6190D88EF52C0F159E8529AA91EC0921FB55539FC52C018B23835651F21C044BC358D033853C0ACE8D577DFD720C020939A44522B53C01BC722D88E1A1EC0', 1608, 1608, 4989, -8.06359999999999921, -76.2639000000000067, 'S 08 03 49', 'O 76 15 50', 189, 109);
INSERT INTO bdc.mux_grid VALUES ('189/110', '0106000020E61000000100000001030000000100000005000000E4D6D534053853C07725157DDDD720C068CAFC8D3CFC52C0CAA4315B611F21C04DDE4AD8F70853C0028DA360ECE922C0C8EA237FC04453C0AE0D878268A222C0E4D6D534053853C07725157DDDD720C0', 1609, 1609, 4990, -8.95919999999999916, -76.4626999999999981, 'S 08 57 33', 'O 76 27 45', 189, 110);
INSERT INTO bdc.mux_grid VALUES ('189/111', '0106000020E61000000100000001030000000100000005000000D0223359C24453C039A4714B66A222C0A0900871FB0853C034C93813E8E922C0C84CD5E3C11553C08F8D85A764B424C0F6DEFFCB885153C09368BEDFE26C24C0D0223359C24453C039A4714B66A222C0', 1610, 1610, 4991, -9.85479999999999912, -76.6621999999999986, 'S 09 51 17', 'O 76 39 43', 189, 111);
INSERT INTO bdc.mux_grid VALUES ('189/112', '0106000020E610000001000000010300000001000000050000005E4667D98A5153C0AD8A3D6BE06C24C08AA8CEDEC51553C0416D98E45FB424C036C48FA6982253C0FD72B79BCC7E26C00A6228A15D5E53C068905C224D3726C05E4667D98A5153C0AD8A3D6BE06C24C0', 1611, 1611, 4993, -10.7501999999999995, -76.8623000000000047, 'S 10 45 00', 'O 76 51 44', 189, 112);
INSERT INTO bdc.mux_grid VALUES ('189/87', '0106000020E610000001000000010300000001000000050000003D089F856F1552C073BAA7AD985D284018046CC9ADD951C0111CA5151D162840F28EBB5595E651C0172C8E51CA4B26401793EE11572252C079CA90E9459326403D089F856F1552C073BAA7AD985D2840', 1612, 1612, 5026, 11.6454000000000004, -71.9239000000000033, 'N 11 38 43', 'O 71 55 26', 189, 87);
INSERT INTO bdc.mux_grid VALUES ('189/88', '0106000020E61000000100000001030000000100000005000000CCE1608E542252C01470BAE7429326401C45729C90E651C0DDDAF8AAC44B2640BAF326056AF351C06C1BCBE15F8124406A9015F72D2F52C0A2B08C1EDEC82440CCE1608E542252C01470BAE742932640', 1613, 1613, 5027, 10.7501999999999995, -72.1248999999999967, 'N 10 45 00', 'O 72 07 29', 189, 88);
INSERT INTO bdc.mux_grid VALUES ('189/89', '0106000020E610000001000000010300000001000000050000005E5C4AA92B2F52C0CC6C055DDBC824407895FDB165F351C07CE75FB55A812440D6FB2B2D320052C0BA358258E5B62240BCC27824F83B52C009BB270066FE22405E5C4AA92B2F52C0CC6C055DDBC82440', 1614, 1614, 5028, 9.85479999999999912, -72.3251000000000062, 'N 09 51 17', 'O 72 19 30', 189, 89);
INSERT INTO bdc.mux_grid VALUES ('189/90', '0106000020E610000001000000010300000001000000050000000408490BF63B52C0E1A58E7D63FE22403E25F93D2E0052C0D623ABA3E0B62240B8EE14FBEE0C52C0035CBA225CEC20407ED164C8B64852C00EDE9DFCDE3321400408490BF63B52C0E1A58E7D63FE2240', 1615, 1615, 5029, 8.95919999999999916, -72.5245000000000033, 'N 08 57 33', 'O 72 31 28', 189, 90);
INSERT INTO bdc.mux_grid VALUES ('189/91', '0106000020E61000000100000001030000000100000005000000AA0DC6E2B44852C02229B4B7DC332140DC31E56DEB0C52C096FD21E357EC2040CCCD6896A11952C079304C588B431E409AA9490B6B5552C08D87700195D21E40AA0DC6E2B44852C02229B4B7DC332140', 1616, 1616, 5030, 8.06359999999999921, -72.7232999999999947, 'N 08 03 49', 'O 72 43 23', 189, 91);
INSERT INTO bdc.mux_grid VALUES ('189/92', '0106000020E6100000010000000103000000010000000500000014BC4C58695552C013C4BFF090D21E40389B7C699E1952C09D156ABF83431E4062728A214B2652C03433A3BE46AE1A403E935A10166252C0A8E1F8EF533D1B4014BC4C58695552C013C4BFF090D21E40', 1617, 1617, 5032, 7.16790000000000038, -72.9214000000000055, 'N 07 10 04', 'O 72 55 17', 189, 92);
INSERT INTO bdc.mux_grid VALUES ('189/93', '0106000020E610000001000000010300000001000000050000000CBD2A8F146252C027C86D56503D1B400A3F5453482652C0669F580840AE1A40882E52BAEC3252C029AA994BED1817408AAC28F6B86E52C0EBD2AE99FDA717400CBD2A8F146252C027C86D56503D1B40', 1618, 1618, 5034, 6.27210000000000001, -73.1191000000000031, 'N 06 16 19', 'O 73 07 08', 189, 93);
INSERT INTO bdc.mux_grid VALUES ('189/94', '0106000020E6100000010000000103000000010000000500000004AF0AA6B76E52C0BF698975FAA7174031D17449EA3252C0FA42A374E7181740F69BA27A873F52C00D8AA4D081831340CA7938D7547B52C0D1B08AD19412144004AF0AA6B76E52C0BF698975FAA71740', 1619, 1619, 5035, 5.37619999999999987, -73.3162999999999982, 'N 05 22 34', 'O 73 18 58', 189, 94);
INSERT INTO bdc.mux_grid VALUES ('189/95', '0106000020E6100000010000000103000000010000000500000020D189B7537B52C09F2846219212144082E0EF65853F52C01E4D2FD67C8313400C40F9781C4C52C096E6AA3B0EDC0F40AC3093CAEA8752C0CC4EEC681C7D104020D189B7537B52C09F28462192121440', 1620, 1620, 5037, 4.48029999999999973, -73.5130999999999943, 'N 04 28 49', 'O 73 30 47', 189, 95);
INSERT INTO bdc.mux_grid VALUES ('189/96', '0106000020E61000000100000001030000000100000005000000586AC9DAE98752C0D76C3D2B1A7D104024AE70BF1A4C52C02691F7FA05DC0F4014A3FBC8AC5852C0C3993A0400B108404A5F54E47B9452C04BE2BD5F2ECF0940586AC9DAE98752C0D76C3D2B1A7D1040', 1621, 1621, 5038, 3.58429999999999982, -73.7095999999999947, 'N 03 35 03', 'O 73 42 34', 189, 96);
INSERT INTO bdc.mux_grid VALUES ('189/97', '0106000020E61000000100000001030000000100000005000000EA89FC237B9452C0CE6C65C72ACF09405075C969AB5852C0271AC973F9B008407C71017C396552C0DE641597DE8501401686343609A152C086B7B1EA0FA40240EA89FC237B9452C0CE6C65C72ACF0940', 1622, 1622, 5039, 2.68829999999999991, -73.9057999999999993, 'N 02 41 17', 'O 73 54 20', 189, 97);
INSERT INTO bdc.mux_grid VALUES ('189/98', '0106000020E61000000100000001030000000100000005000000BCBAF2A408A152C019D2A6330DA402405ABC7D76386552C0853FC2B3D9850140CE3A9CA1C37152C0AC12141E5FB5F43F303911D093AD52C0D537DD1DC6F1F63FBCBAF2A408A152C019D2A6330DA40240', 1623, 1623, 5040, 1.79220000000000002, -74.1019000000000005, 'N 01 47 31', 'O 74 06 06', 189, 98);
INSERT INTO bdc.mux_grid VALUES ('189/99', '0106000020E61000000100000001030000000100000005000000D03CA06D93AD52C09B06CC6FC2F1F63FD2404AF5C27152C062BE00AD58B5F43F605B1D484C7E52C0383B4E30C47BD93F5E5773C01CBA52C0FBADBD9DB536E13FD03CA06D93AD52C09B06CC6FC2F1F63F', 1624, 1624, 5041, 0.896100000000000008, -74.2977999999999952, 'N 00 53 45', 'O 74 17 51', 189, 99);
INSERT INTO bdc.mux_grid VALUES ('190/100', '0106000020E6100000010000000103000000010000000500000094077786E1F752C0960D24BEB136E13FC4C17DEE10BC52C068AC07B6B77BD93F7850ED7699C852C0A759525307DEDFBF4896E60E6A0453C0E3EA118D5BECD6BF94077786E1F752C0960D24BEB136E13F', 1625, 1625, 5043, 0, -75.4587999999999965, 'N 00 00 00', 'O 75 27 31', 190, 100);
INSERT INTO bdc.mux_grid VALUES ('190/101', '0106000020E6100000010000000103000000010000000500000030EAA0096A0453C03676E2565CECD6BF8CFC327C99C852C003CF818906DEDFBFA0C8C44722D552C0F7FDAB51EE4DF6BF44B632D5F21053C0CD2704C58311F4BF30EAA0096A0453C03676E2565CECD6BF', 1626, 1626, 5045, -0.896100000000000008, -75.6546000000000021, 'S 00 53 45', 'O 75 39 16', 190, 101);
INSERT INTO bdc.mux_grid VALUES ('190/102', '0106000020E6100000010000000103000000010000000500000063DC73FEF21053C005BD373A8211F4BF6CEEC4A522D552C063261ACEEA4DF6BFBE8020C2ACE152C02D5B579B245202C0B36ECF1A7D1D53C07E266651F03301C063DC73FEF21053C005BD373A8211F4BF', 1627, 1627, 5046, -1.79220000000000002, -75.8504999999999967, 'S 01 47 31', 'O 75 51 01', 190, 102);
INSERT INTO bdc.mux_grid VALUES ('190/103', '0106000020E610000001000000010300000001000000050000001EFBAA727D1D53C0DBFB01ADEE3301C03CD60779ADE152C0DBA42930215202C0C4687AF439EE52C0A5F73AA7437D09C0A48D1DEE092A53C0A54E1324115F08C01EFBAA727D1D53C0DBFB01ADEE3301C0', 1628, 1628, 5048, -2.68829999999999991, -76.0464999999999947, 'S 02 41 17', 'O 76 02 47', 190, 103);
INSERT INTO bdc.mux_grid VALUES ('190/104', '0106000020E61000000100000001030000000100000005000000F441BD740A2A53C0F061E99F0E5F08C04607A0043BEE52C012B407913E7D09C00E21A1EECAFA52C0A6F04658275410C0BC5BBE5E9A3653C0298F6FBF1E8A0FC0F441BD740A2A53C0F061E99F0E5F08C0', 1629, 1629, 5049, -3.58429999999999982, -76.2428000000000026, 'S 03 35 03', 'O 76 14 33', 190, 104);
INSERT INTO bdc.mux_grid VALUES ('190/105', '0106000020E61000000100000001030000000100000005000000165262149B3653C047274D5A1B8A0FC0E9DD8658CCFA52C051E973F6235410C066223EC2600753C03CBDD50CA0E913C09496197E2F4353C08F6788C3895A13C0165262149B3653C047274D5A1B8A0FC0', 1630, 1630, 5050, -4.48029999999999973, -76.4391999999999996, 'S 04 28 49', 'O 76 26 21', 190, 105);
INSERT INTO bdc.mux_grid VALUES ('190/106', '0106000020E6100000010000000103000000010000000500000066831863304353C0F485AB9F875A13C064139186620753C00A37ABD29BE913C01CD05D83FC1353C0ADE66221097F17C01E40E55FCA4F53C0973563EEF4EF16C066831863304353C0F485AB9F875A13C0', 1631, 1631, 5051, -5.37619999999999987, -76.636099999999999, 'S 05 22 34', 'O 76 38 09', 190, 106);
INSERT INTO bdc.mux_grid VALUES ('190/107', '0106000020E610000001000000010300000001000000050000009ACBAC74CB4F53C0D04C3458F2EF16C0A0FCF6A2FE1353C015A6D90C047F17C0E002FA489F2053C0DF5CB3C45F141BC0D9D1AF1A6C5C53C09A030E104E851AC09ACBAC74CB4F53C0D04C3458F2EF16C0', 1632, 1632, 5053, -6.27210000000000001, -76.8332999999999942, 'S 06 16 19', 'O 76 49 59', 190, 107);
INSERT INTO bdc.mux_grid VALUES ('190/108', '0106000020E610000001000000010300000001000000050000007609C55F6D5C53C009C14E064B851AC0E642DFC4A12053C0BCEE58D359141BC0A89F872D4A2D53C01129F423A1A91EC036666DC8156953C05CFBE956921A1EC07609C55F6D5C53C009C14E064B851AC0', 1633, 1633, 5054, -7.16790000000000038, -77.0309000000000026, 'S 07 10 04', 'O 77 01 51', 190, 108);
INSERT INTO bdc.mux_grid VALUES ('190/109', '0106000020E61000000100000001030000000100000005000000E6466D3E176953C0A1C822D88E1A1EC046AAEC064D2D53C04E5BE8529AA91EC064D3874FFE3953C046B23835651F21C006700887C87553C0EFE8D577DFD720C0E6466D3E176953C0A1C822D88E1A1EC0', 1634, 1634, 5056, -8.06359999999999921, -77.2291000000000025, 'S 08 03 49', 'O 77 13 44', 190, 109);
INSERT INTO bdc.mux_grid VALUES ('190/110', '0106000020E61000000100000001030000000100000005000000A88AA82ECA7553C0BA25157DDDD720C03D7ECF87013A53C0F8A4315B611F21C01E921DD2BC4653C0308DA360ECE922C08A9EF678858253C0F10D878268A222C0A88AA82ECA7553C0BA25157DDDD720C0', 1635, 1635, 5057, -8.95919999999999916, -77.427899999999994, 'S 08 57 33', 'O 77 25 40', 190, 110);
INSERT INTO bdc.mux_grid VALUES ('190/111', '0106000020E61000000100000001030000000100000005000000ABD60553878253C05DA4714B66A222C06844DB6AC04653C06FC93813E8E922C09000A8DD865353C0CB8D85A764B424C0D092D2C54D8F53C0BA68BEDFE26C24C0ABD60553878253C05DA4714B66A222C0', 1636, 1636, 5059, -9.85479999999999912, -77.6273000000000053, 'S 09 51 17', 'O 77 37 38', 190, 111);
INSERT INTO bdc.mux_grid VALUES ('190/88', '0106000020E61000000100000001030000000100000005000000A4953388196052C07070BAE742932640E2F84496552452C024DBF8AAC44B264080A7F9FE2E3152C0B21BCBE15F8124404244E8F0F26C52C0FEB08C1EDEC82440A4953388196052C07070BAE742932640', 1637, 1637, 5088, 10.7501999999999995, -73.0900000000000034, 'N 10 45 00', 'O 73 05 24', 190, 88);
INSERT INTO bdc.mux_grid VALUES ('190/89', '0106000020E6100000010000000103000000010000000500000040101DA3F06C52C0376D055DDBC824403849D0AB2A3152C0BDE75FB55A8124409AAFFE26F73D52C07B358258E5B62240A2764B1EBD7952C0F4BA270066FE224040101DA3F06C52C0376D055DDBC82440', 1638, 1638, 5089, 9.85479999999999912, -73.2901999999999987, 'N 09 51 17', 'O 73 17 24', 190, 89);
INSERT INTO bdc.mux_grid VALUES ('190/90', '0106000020E61000000100000001030000000100000005000000E0BB1B05BB7952C0BEA58E7D63FE224018D9CB37F33D52C0B323ABA3E0B6224094A2E7F4B34A52C0E05BBA225CEC20405A8537C27B8652C0EBDD9DFCDE332140E0BB1B05BB7952C0BEA58E7D63FE2240', 1639, 1639, 5090, 8.95919999999999916, -73.4895999999999958, 'N 08 57 33', 'O 73 29 22', 190, 90);
INSERT INTO bdc.mux_grid VALUES ('190/91', '0106000020E6100000010000000103000000010000000500000080C198DC798652C0F828B4B7DC332140A0E5B767B04A52C058FD21E357EC20408E813B90665752C0FA304C588B431E406E5D1C05309352C03788700195D21E4080C198DC798652C0F828B4B7DC332140', 1640, 1640, 5092, 8.06359999999999921, -73.6884000000000015, 'N 08 03 49', 'O 73 41 18', 190, 91);
INSERT INTO bdc.mux_grid VALUES ('190/92', '0106000020E61000000100000001030000000100000005000000E06F1F522E9352C0ADC4BFF090D21E40044F4F63635752C039166ABF83431E4030265D1B106452C04F33A3BE46AE1A400C472D0ADB9F52C0C2E1F8EF533D1B40E06F1F522E9352C0ADC4BFF090D21E40', 1641, 1641, 5093, 7.16790000000000038, -73.8866000000000014, 'N 07 10 04', 'O 73 53 11', 190, 92);
INSERT INTO bdc.mux_grid VALUES ('190/93', '0106000020E61000000100000001030000000100000005000000E470FD88D99F52C05BC86D56503D1B40D8F2264D0D6452C0859F580840AE1A405AE224B4B17052C047A9994BED1817406660FBEF7DAC52C01CD2AE99FDA71740E470FD88D99F52C05BC86D56503D1B40', 1642, 1642, 5095, 6.27210000000000001, -74.0841999999999956, 'N 06 16 19', 'O 74 05 03', 190, 93);
INSERT INTO bdc.mux_grid VALUES ('190/94', '0106000020E61000000100000001030000000100000005000000D462DD9F7CAC52C0D7688975FAA717400A854743AF7052C02842A374E7181740CE4F75744C7D52C0B989A4D0818313409A2D0BD119B952C069B08AD194121440D462DD9F7CAC52C0D7688975FAA71740', 1643, 1643, 5096, 5.37619999999999987, -74.281400000000005, 'N 05 22 34', 'O 74 16 53', 190, 94);
INSERT INTO bdc.mux_grid VALUES ('190/95', '0106000020E61000000100000001030000000100000005000000F4845CB118B952C045284621921214405694C25F4A7D52C0C24C2FD67C831340DEF3CB72E18952C0DDE6AA3B0EDC0F407EE465C4AFC552C0F24EEC681C7D1040F4845CB118B952C04528462192121440', 1644, 1644, 5097, 4.48029999999999973, -74.4783000000000044, 'N 04 28 49', 'O 74 28 41', 190, 95);
INSERT INTO bdc.mux_grid VALUES ('190/96', '0106000020E610000001000000010300000001000000050000002C1E9CD4AEC552C0FF6C3D2B1A7D1040EE6143B9DF8952C04D91F7FA05DC0F40E056CEC2719652C068993A0400B108401E1327DE40D252C01CE2BD5F2ECF09402C1E9CD4AEC552C0FF6C3D2B1A7D1040', 1645, 1645, 5098, 3.58429999999999982, -74.6747000000000014, 'N 03 35 03', 'O 74 40 29', 190, 96);
INSERT INTO bdc.mux_grid VALUES ('190/97', '0106000020E61000000100000001030000000100000005000000BA3DCF1D40D252C0906C65C72ACF094020299C63709652C0E819C973F9B008404C25D475FEA252C0A0641597DE850140E6390730CEDE52C047B7B1EA0FA40240BA3DCF1D40D252C0906C65C72ACF0940', 1646, 1646, 5099, 2.68829999999999991, -74.8709999999999951, 'N 02 41 17', 'O 74 52 15', 190, 97);
INSERT INTO bdc.mux_grid VALUES ('190/98', '0106000020E61000000100000001030000000100000005000000926EC59ECDDE52C0F5D1A6330DA402402C705070FDA252C04B3FC2B3D9850140A0EE6E9B88AF52C0BE12141E5FB5F43F06EDE3C958EB52C01338DD1DC6F1F63F926EC59ECDDE52C0F5D1A6330DA40240', 1647, 1647, 5100, 1.79220000000000002, -75.0669999999999931, 'N 01 47 31', 'O 75 04 01', 190, 98);
INSERT INTO bdc.mux_grid VALUES ('190/99', '0106000020E61000000100000001030000000100000005000000A2F0726758EB52C0AD06CC6FC2F1F63FA2F41CEF87AF52C062BE00AD58B5F43F300FF04111BC52C03E3A4E30C47BD93F320B46BAE1F752C0C6ADBD9DB536E13FA2F0726758EB52C0AD06CC6FC2F1F63F', 1648, 1648, 5102, 0.896100000000000008, -75.2629000000000019, 'N 00 53 45', 'O 75 15 46', 190, 99);
INSERT INTO bdc.mux_grid VALUES ('191/100', '0106000020E6100000010000000103000000010000000500000064BB4980A63553C0FB0D24BEB136E13F947550E8D5F952C014AD07B6B77BD93F4A04C0705E0653C00D59525307DEDFBF184AB9082F4253C04CEA118D5BECD6BF64BB4980A63553C0FB0D24BEB136E13F', 1649, 1649, 5103, 0, -76.4239000000000033, 'N 00 00 00', 'O 76 25 26', 191, 100);
INSERT INTO bdc.mux_grid VALUES ('191/101', '0106000020E61000000100000001030000000100000005000000029E73032F4253C07C75E2565CECD6BF5EB005765E0653C042CE818906DEDFBF747C9741E71253C009FEAB51EE4DF6BF186A05CFB74E53C0D82704C58311F4BF029E73032F4253C07C75E2565CECD6BF', 1650, 1650, 5105, -0.896100000000000008, -76.6196999999999946, 'S 00 53 45', 'O 76 37 11', 191, 101);
INSERT INTO bdc.mux_grid VALUES ('191/102', '0106000020E61000000100000001030000000100000005000000349046F8B74E53C022BD373A8211F4BF3CA2979FE71253C09A261ACEEA4DF6BF8A34F3BB711F53C0EA5A579B245202C08222A214425B53C032266651F03301C0349046F8B74E53C022BD373A8211F4BF', 1651, 1651, 5107, -1.79220000000000002, -76.8156000000000034, 'S 01 47 31', 'O 76 48 56', 191, 102);
INSERT INTO bdc.mux_grid VALUES ('191/103', '0106000020E61000000100000001030000000100000005000000EAAE7D6C425B53C0A0FB01ADEE3301C00E8ADA72721F53C08DA42930215202C0941C4DEEFE2B53C063F73AA7437D09C06E41F0E7CE6753C0764E1324115F08C0EAAE7D6C425B53C0A0FB01ADEE3301C0', 1652, 1652, 5108, -2.68829999999999991, -77.0117000000000047, 'S 02 41 17', 'O 77 00 42', 191, 103);
INSERT INTO bdc.mux_grid VALUES ('191/104', '0106000020E61000000100000001030000000100000005000000C4F58F6ECF6753C0B261E99F0E5F08C016BB72FEFF2B53C0D4B307913E7D09C0DED473E88F3853C04CF04658275410C08C0F91585F7453C0768E6FBF1E8A0FC0C4F58F6ECF6753C0B261E99F0E5F08C0', 1653, 1653, 5109, -3.58429999999999982, -77.2078999999999951, 'S 03 35 03', 'O 77 12 28', 191, 104);
INSERT INTO bdc.mux_grid VALUES ('191/105', '0106000020E61000000100000001030000000100000005000000DE05350E607453C0AF264D5A1B8A0FC0BA915952913853C0F0E873F6235410C039D610BC254553C055BDD50CA0E913C05C4AEC77F48053C0BC6788C3895A13C0DE05350E607453C0AF264D5A1B8A0FC0', 1654, 1654, 5110, -4.48029999999999973, -77.4043999999999954, 'S 04 28 49', 'O 77 24 15', 191, 105);
INSERT INTO bdc.mux_grid VALUES ('191/106', '0106000020E610000001000000010300000001000000050000003237EB5CF58053C01C86AB9F875A13C036C76380274553C02037ABD29BE913C0F083307DC15153C00BE76221097F17C0EAF3B7598F8D53C0063663EEF4EF16C03237EB5CF58053C01C86AB9F875A13C0', 1655, 1655, 5112, -5.37619999999999987, -77.6012000000000057, 'S 05 22 34', 'O 77 36 04', 191, 106);
INSERT INTO bdc.mux_grid VALUES ('191/107', '0106000020E61000000100000001030000000100000005000000707F7F6E908D53C0294D3458F2EF16C070B0C99CC35153C084A6D90C047F17C0ACB6CC42645E53C0945CB3C45F141BC0AE858214319A53C038030E104E851AC0707F7F6E908D53C0294D3458F2EF16C0', 1656, 1656, 5113, -6.27210000000000001, -77.7984000000000009, 'S 06 16 19', 'O 77 47 54', 191, 107);
INSERT INTO bdc.mux_grid VALUES ('191/108', '0106000020E6100000010000000103000000010000000500000044BD9759329A53C0B1C04E064B851AC0B6F6B1BE665E53C067EE58D359141BC076535A270F6B53C08228F423A1A91EC0041A40C2DAA653C0CCFAE956921A1EC044BD9759329A53C0B1C04E064B851AC0', 1657, 1657, 5114, -7.16790000000000038, -77.9960999999999984, 'S 07 10 04', 'O 77 59 45', 191, 108);
INSERT INTO bdc.mux_grid VALUES ('191/109', '0106000020E61000000100000001030000000100000005000000C6FA3F38DCA653C0E0C722D88E1A1EC0045EBF00126B53C0E15AE8529AA91EC028875A49C37753C0C1B23835651F21C0EA23DB808DB353C040E9D577DFD720C0C6FA3F38DCA653C0E0C722D88E1A1EC0', 1658, 1658, 5116, -8.06359999999999921, -78.194199999999995, 'S 08 03 49', 'O 78 11 39', 191, 109);
INSERT INTO bdc.mux_grid VALUES ('191/88', '0106000020E610000001000000010300000001000000050000006E490682DE9D52C0F86FBAE742932640BEAC17901A6252C0C1DAF8AAC44B2640585BCCF8F36E52C0EE1BCBE15F81244008F8BAEAB7AA52C024B18C1EDEC824406E490682DE9D52C0F86FBAE742932640', 1659, 1659, 5143, 10.7501999999999995, -74.0551999999999992, 'N 10 45 00', 'O 74 03 18', 191, 88);
INSERT INTO bdc.mux_grid VALUES ('191/89', '0106000020E6100000010000000103000000010000000500000002C4EF9CB5AA52C0586D055DDBC824401CFDA2A5EF6E52C008E85FB55A8124407E63D120BC7B52C0E2358258E5B62240642A1E1882B752C032BB270066FE224002C4EF9CB5AA52C0586D055DDBC82440', 1660, 1660, 5144, 9.85479999999999912, -74.2553000000000054, 'N 09 51 17', 'O 74 15 19', 191, 89);
INSERT INTO bdc.mux_grid VALUES ('191/90', '0106000020E61000000100000001030000000100000005000000A66FEEFE7FB752C004A68E7D63FE2240F28C9E31B87B52C00D24ABA3E0B622406D56BAEE788852C0575CBA225CEC204020390ABC40C452C04DDE9DFCDE332140A66FEEFE7FB752C004A68E7D63FE2240', 1661, 1661, 5146, 8.95919999999999916, -74.4548000000000059, 'N 08 57 33', 'O 74 27 17', 191, 90);
INSERT INTO bdc.mux_grid VALUES ('191/91', '0106000020E6100000010000000103000000010000000500000054756BD63EC452C06829B4B7DC33214074998A61758852C0C9FD21E357EC204064350E8A2B9552C0A9304C588B431E404611EFFEF4D052C0E987700195D21E4054756BD63EC452C06829B4B7DC332140', 1662, 1662, 5147, 8.06359999999999921, -74.6535999999999973, 'N 08 03 49', 'O 74 39 12', 191, 91);
INSERT INTO bdc.mux_grid VALUES ('191/92', '0106000020E61000000100000001030000000100000005000000C023F24BF3D052C074C4BFF090D21E40D202225D289552C0D8156ABF83431E40FED92F15D5A152C02A33A3BE46AE1A40ECFAFF03A0DD52C0C4E1F8EF533D1B40C023F24BF3D052C074C4BFF090D21E40', 1663, 1663, 5148, 7.16790000000000038, -74.8516999999999939, 'N 07 10 04', 'O 74 51 06', 191, 92);
INSERT INTO bdc.mux_grid VALUES ('191/93', '0106000020E61000000100000001030000000100000005000000AC24D0829EDD52C025C86D56503D1B40B2A6F946D2A152C0789F580840AE1A403296F7AD76AE52C075A9994BED1817402C14CEE942EA52C022D2AE99FDA71740AC24D0829EDD52C025C86D56503D1B40', 1664, 1664, 5150, 6.27210000000000001, -75.0494000000000057, 'N 06 16 19', 'O 75 02 57', 191, 93);
INSERT INTO bdc.mux_grid VALUES ('191/94', '0106000020E61000000100000001030000000100000005000000AC16B09941EA52C000698975FAA71740D6381A3D74AE52C03A42A374E71817409C03486E11BB52C08889A4D08183134070E1DDCADEF652C04EB08AD194121440AC16B09941EA52C000698975FAA71740', 1665, 1665, 5152, 5.37619999999999987, -75.2466000000000008, 'N 05 22 34', 'O 75 14 47', 191, 94);
INSERT INTO bdc.mux_grid VALUES ('191/95', '0106000020E61000000100000001030000000100000005000000C6382FABDDF652C02028462192121440284895590FBB52C09C4C2FD67C831340B2A79E6CA6C752C00AE6AA3B0EDC0F40509838BE740353C0884EEC681C7D1040C6382FABDDF652C02028462192121440', 1666, 1666, 5153, 4.48029999999999973, -75.4433999999999969, 'N 04 28 49', 'O 75 26 36', 191, 95);
INSERT INTO bdc.mux_grid VALUES ('191/96', '0106000020E6100000010000000103000000010000000500000002D26ECE730353C0956C3D2B1A7D1040C41516B3A4C752C07A90F7FA05DC0F40B40AA1BC36D452C0FC993A0400B10840F0C6F9D7051053C0ADE2BD5F2ECF094002D26ECE730353C0956C3D2B1A7D1040', 1667, 1667, 5154, 3.58429999999999982, -75.6398999999999972, 'N 03 35 03', 'O 75 38 23', 191, 96);
INSERT INTO bdc.mux_grid VALUES ('191/97', '0106000020E6100000010000000103000000010000000500000090F1A117051053C0276D65C72ACF0940F0DC6E5D35D452C0691AC973F9B008401ED9A66FC3E052C098641597DE850140BCEDD929931C53C056B7B1EA0FA4024090F1A117051053C0276D65C72ACF0940', 1668, 1668, 5155, 2.68829999999999991, -75.8361000000000018, 'N 02 41 17', 'O 75 50 10', 191, 97);
INSERT INTO bdc.mux_grid VALUES ('191/98', '0106000020E6100000010000000103000000010000000500000064229898921C53C0F2D1A6330DA402400224236AC2E052C05F3FC2B3D985014076A241954DED52C0E512141E5FB5F43FD6A0B6C31D2953C00C38DD1DC6F1F63F64229898921C53C0F2D1A6330DA40240', 1669, 1669, 5157, 1.79220000000000002, -76.0322000000000031, 'N 01 47 31', 'O 76 01 55', 191, 98);
INSERT INTO bdc.mux_grid VALUES ('191/99', '0106000020E6100000010000000103000000010000000500000074A445611D2953C0C006CC6FC2F1F63F74A8EFE84CED52C06EBE00AD58B5F43F05C3C23BD6F952C0323B4E30C47BD93F05BF18B4A63553C02CAEBD9DB536E13F74A445611D2953C0C006CC6FC2F1F63F', 1670, 1670, 5158, 0.896100000000000008, -76.2280999999999977, 'N 00 53 45', 'O 76 13 41', 191, 99);
INSERT INTO bdc.mux_grid VALUES ('192/100', '0106000020E61000000100000001030000000100000005000000346F1C7A6B7353C0BA0D24BEB136E13F662923E29A3753C0B0AC07B6B77BD93F1CB8926A234453C03D59525307DEDFBFEAFD8B02F47F53C077EA118D5BECD6BF346F1C7A6B7353C0BA0D24BEB136E13F', 1671, 1671, 5159, 0, -77.3889999999999958, 'N 00 00 00', 'O 77 23 20', 192, 100);
INSERT INTO bdc.mux_grid VALUES ('192/101', '0106000020E61000000100000001030000000100000005000000D25146FDF37F53C0CB75E2565CECD6BF3064D86F234453C006CE818906DEDFBF46306A3BAC5053C0C1FDAB51EE4DF6BFE81DD8C87C8C53C0B22704C58311F4BFD25146FDF37F53C0CB75E2565CECD6BF', 1672, 1672, 5162, -0.896100000000000008, -77.5849000000000046, 'S 00 53 45', 'O 77 35 05', 192, 101);
INSERT INTO bdc.mux_grid VALUES ('192/102', '0106000020E61000000100000001030000000100000005000000054419F27C8C53C0EABC373A8211F4BF0C566A99AC5053C05A261ACEEA4DF6BF5CE8C5B5365D53C02D5B579B245202C056D6740E079953C071266651F03301C0054419F27C8C53C0EABC373A8211F4BF', 1673, 1673, 5163, -1.79220000000000002, -77.7807999999999993, 'S 01 47 31', 'O 77 46 50', 192, 102);
INSERT INTO bdc.mux_grid VALUES ('192/103', '0106000020E61000000100000001030000000100000005000000BC625066079953C0E0FB01ADEE3301C0DC3DAD6C375D53C0DFA42930215202C062D01FE8C36953C0A9F73AA7437D09C042F5C2E193A553C0AA4E1324115F08C0BC625066079953C0E0FB01ADEE3301C0', 1674, 1674, 5164, -2.68829999999999991, -77.9767999999999972, 'S 02 41 17', 'O 77 58 36', 192, 103);
INSERT INTO bdc.mux_grid VALUES ('192/104', '0106000020E6100000010000000103000000010000000500000092A9626894A553C00162E99F0E5F08C0E86E45F8C46953C00DB407913E7D09C0B08846E2547653C0E2F04658275410C05AC3635224B253C0B88F6FBF1E8A0FC092A9626894A553C00162E99F0E5F08C0', 1675, 1675, 5165, -3.58429999999999982, -78.1731000000000051, 'S 03 35 03', 'O 78 10 23', 192, 104);
INSERT INTO bdc.mux_grid VALUES ('192/105', '0106000020E61000000100000001030000000100000005000000B2B9070825B253C0D6274D5A1B8A0FC086452C4C567653C09BE973F6235410C0028AE3B5EA8253C009BDD50CA0E913C02EFEBE71B9BE53C0596788C3895A13C0B2B9070825B253C0D6274D5A1B8A0FC0', 1676, 1676, 5167, -4.48029999999999973, -78.3695000000000022, 'S 04 28 49', 'O 78 22 10', 192, 105);
INSERT INTO bdc.mux_grid VALUES ('192/106', '0106000020E6100000010000000103000000010000000500000004EBBD56BABE53C0BA85AB9F875A13C0007B367AEC8253C0CF36ABD29BE913C0BA370377868F53C0F5E66221097F17C0BCA78A5354CB53C0DF3563EEF4EF16C004EBBD56BABE53C0BA85AB9F875A13C0', 1677, 1677, 5168, -5.37619999999999987, -78.5664000000000016, 'S 05 22 34', 'O 78 33 58', 192, 106);
INSERT INTO bdc.mux_grid VALUES ('192/107', '0106000020E610000001000000010300000001000000050000003A33526855CB53C0114D3458F2EF16C042649C96888F53C056A6D90C047F17C0806A9F3C299C53C09E5CB3C45F141BC07839550EF6D753C059030E104E851AC03A33526855CB53C0114D3458F2EF16C0', 1678, 1678, 5169, -6.27210000000000001, -78.7635999999999967, 'S 06 16 19', 'O 78 45 48', 192, 107);
INSERT INTO bdc.mux_grid VALUES ('192/108', '0106000020E6100000010000000103000000010000000500000014716A53F7D753C0CCC04E064B851AC086AA84B82B9C53C082EE58D359141BC042072D21D4A853C0D827F423A1A91EC0D0CD12BC9FE453C024FAE956921A1EC014716A53F7D753C0CCC04E064B851AC0', 1679, 1679, 5170, -7.16790000000000038, -78.9612000000000052, 'S 07 10 04', 'O 78 57 40', 192, 108);
INSERT INTO bdc.mux_grid VALUES ('192/89', '0106000020E61000000100000001030000000100000005000000D677C2967AE852C04E6D055DDBC82440E1B0759FB4AC52C0E9E75FB55A8124403E17A41A81B952C026368258E5B6224036DEF01147F552C08BBB270066FE2240D677C2967AE852C04E6D055DDBC82440', 1680, 1680, 5195, 9.85479999999999912, -75.2205000000000013, 'N 09 51 17', 'O 75 13 13', 192, 89);
INSERT INTO bdc.mux_grid VALUES ('192/90', '0106000020E610000001000000010300000001000000050000006C23C1F844F552C050A68E7D63FE2240B840712B7DB952C05924ABA3E0B62240380A8DE83DC652C0055CBA225CEC2040ECECDCB5050253C0FCDD9DFCDE3321406C23C1F844F552C050A68E7D63FE2240', 1681, 1681, 5196, 8.95919999999999916, -75.4198999999999984, 'N 08 57 33', 'O 75 25 11', 192, 90);
INSERT INTO bdc.mux_grid VALUES ('192/91', '0106000020E610000001000000010300000001000000050000002A293ED0030253C02629B4B7DC3321404A4D5D5B3AC652C086FD21E357EC204036E9E083F0D252C052314C588B431E4016C5C1F8B90E53C08F88700195D21E402A293ED0030253C02629B4B7DC332140', 1682, 1682, 5197, 8.06359999999999921, -75.618700000000004, 'N 08 03 49', 'O 75 37 07', 192, 91);
INSERT INTO bdc.mux_grid VALUES ('192/92', '0106000020E610000001000000010300000001000000050000007CD7C445B80E53C0E3C4BFF090D21E40B0B6F456EDD252C09A166ABF83431E40E08D020F9ADF52C02E33A3BE46AE1A40AAAED2FD641B53C076E1F8EF533D1B407CD7C445B80E53C0E3C4BFF090D21E40', 1683, 1683, 5198, 7.16790000000000038, -75.816900000000004, 'N 07 10 04', 'O 75 49 00', 192, 92);
INSERT INTO bdc.mux_grid VALUES ('192/93', '0106000020E610000001000000010300000001000000050000007ED8A27C631B53C005C86D56503D1B407A5ACC4097DF52C0419F580840AE1A40FA49CAA73BEC52C083A9994BED181740FCC7A0E3072853C047D2AE99FDA717407ED8A27C631B53C005C86D56503D1B40', 1684, 1684, 5201, 6.27210000000000001, -76.0144999999999982, 'N 06 16 19', 'O 76 00 52', 192, 93);
INSERT INTO bdc.mux_grid VALUES ('192/94', '0106000020E6100000010000000103000000010000000500000076CA8293062853C01D698975FAA71740ACECEC3639EC52C06C42A374E718174072B71A68D6F852C07F89A4D0818313403E95B0C4A33453C02FB08AD19412144076CA8293062853C01D698975FAA71740', 1685, 1685, 5202, 5.37619999999999987, -76.2116999999999933, 'N 05 22 34', 'O 76 12 42', 192, 94);
INSERT INTO bdc.mux_grid VALUES ('192/95', '0106000020E610000001000000010300000001000000050000009AEC01A5A23453C01028462192121440FCFB6753D4F852C08C4C2FD67C831340875B71666B0553C072E6AA3B0EDC0F40244C0BB8394153C0BC4EEC681C7D10409AEC01A5A23453C01028462192121440', 1686, 1686, 5203, 4.48029999999999973, -76.408600000000007, 'N 04 28 49', 'O 76 24 30', 192, 95);
INSERT INTO bdc.mux_grid VALUES ('192/96', '0106000020E61000000100000001030000000100000005000000CA8541C8384153C0B76C3D2B1A7D104096C9E8AC690553C0E590F7FA05DC0F4088BE73B6FB1153C08A993A0400B10840BC7ACCD1CA4D53C016E2BD5F2ECF0940CA8541C8384153C0B76C3D2B1A7D1040', 1687, 1687, 5204, 3.58429999999999982, -76.605000000000004, 'N 03 35 03', 'O 76 36 18', 192, 96);
INSERT INTO bdc.mux_grid VALUES ('192/97', '0106000020E6100000010000000103000000010000000500000060A57411CA4D53C0A46C65C72ACF0940C6904157FA1153C0FC19C973F9B00840F08C7969881E53C034651597DE8501408CA1AC23585A53C0DBB7B1EA0FA4024060A57411CA4D53C0A46C65C72ACF0940', 1688, 1688, 5206, 2.68829999999999991, -76.8012999999999977, 'N 02 41 17', 'O 76 48 04', 192, 97);
INSERT INTO bdc.mux_grid VALUES ('192/98', '0106000020E6100000010000000103000000010000000500000030D66A92575A53C06ED2A6330DA40240D2D7F563871E53C0F03FC2B3D98501404856148F122B53C08012141E5FB5F43FA65489BDE26653C07B37DD1DC6F1F63F30D66A92575A53C06ED2A6330DA40240', 1689, 1689, 5207, 1.79220000000000002, -76.9972999999999956, 'N 01 47 31', 'O 76 59 50', 192, 98);
INSERT INTO bdc.mux_grid VALUES ('192/99', '0106000020E610000001000000010300000001000000050000004458185BE26653C03906CC6FC2F1F63F495CC2E2112B53C012BE00AD58B5F43FD87695359B3753C0143B4E30C47BD93FD272EBAD6B7353C0C6ADBD9DB536E13F4458185BE26653C03906CC6FC2F1F63F', 1690, 1690, 5208, 0.896100000000000008, -77.1932000000000045, 'N 00 53 45', 'O 77 11 35', 192, 99);
INSERT INTO bdc.mux_grid VALUES ('193/100', '0106000020E610000001000000010300000001000000050000000623EF7330B153C0DE0D24BEB136E13F38DDF5DB5F7553C0F7AC07B6B77BD93FEC6B6564E88153C01759525307DEDFBFBAB15EFCB8BD53C053EA118D5BECD6BF0623EF7330B153C0DE0D24BEB136E13F', 1691, 1691, 5209, 0, -78.3542000000000058, 'N 00 00 00', 'O 78 21 15', 193, 100);
INSERT INTO bdc.mux_grid VALUES ('193/101', '0106000020E61000000100000001030000000100000005000000A20519F7B8BD53C0A775E2565CECD6BF0018AB69E88153C02ACE818906DEDFBF16E43C35718E53C0CAFDAB51EE4DF6BFBAD1AAC241CA53C0AA2704C58311F4BFA20519F7B8BD53C0A775E2565CECD6BF', 1692, 1692, 5212, -0.896100000000000008, -78.5499999999999972, 'S 00 53 45', 'O 78 33 00', 193, 101);
INSERT INTO bdc.mux_grid VALUES ('193/102', '0106000020E61000000100000001030000000100000005000000D4F7EBEB41CA53C0F3BC373A8211F4BFDE093D93718E53C051261ACEEA4DF6BF309C98AFFB9A53C0635B579B245202C0248A4708CCD653C0B4266651F03301C0D4F7EBEB41CA53C0F3BC373A8211F4BF', 1693, 1693, 5213, -1.79220000000000002, -78.745900000000006, 'S 01 47 31', 'O 78 44 45', 193, 102);
INSERT INTO bdc.mux_grid VALUES ('193/103', '0106000020E610000001000000010300000001000000050000008E162360CCD653C01AFC01ADEE3301C0AEF17F66FC9A53C019A52930215202C03484F2E188A753C0E4F73AA7437D09C014A995DB58E353C0E44E1324115F08C08E162360CCD653C01AFC01ADEE3301C0', 1694, 1694, 5214, -2.68829999999999991, -78.9419999999999931, 'S 02 41 17', 'O 78 56 31', 193, 103);
INSERT INTO bdc.mux_grid VALUES ('193/104', '0106000020E610000001000000010300000001000000050000006C5D356259E353C00E62E99F0E5F08C0B42218F289A753C05EB407913E7D09C07E3C19DC19B453C0CCF04658275410C03477364CE9EF53C0498F6FBF1E8A0FC06C5D356259E353C00E62E99F0E5F08C0', 1695, 1695, 5216, -3.58429999999999982, -79.1381999999999977, 'S 03 35 03', 'O 79 08 17', 193, 104);
INSERT INTO bdc.mux_grid VALUES ('193/105', '0106000020E61000000100000001030000000100000005000000846DDA01EAEF53C08B274D5A1B8A0FC058F9FE451BB453C075E973F6235410C0D63DB6AFAFC053C062BDD50CA0E913C002B2916B7EFC53C0B56788C3895A13C0846DDA01EAEF53C08B274D5A1B8A0FC0', 1696, 1696, 5217, -4.48029999999999973, -79.334699999999998, 'S 04 28 49', 'O 79 20 04', 193, 105);
INSERT INTO bdc.mux_grid VALUES ('193/106', '0106000020E61000000100000001030000000100000005000000D69E90507FFC53C01386AB9F875A13C0D62E0974B1C053C02937ABD29BE913C090EBD5704BCD53C04EE76221097F17C0925B5D4D190954C0393663EEF4EF16C0D69E90507FFC53C01386AB9F875A13C0', 1697, 1697, 5218, -5.37619999999999987, -79.5314999999999941, 'S 05 22 34', 'O 79 31 53', 193, 106);
INSERT INTO bdc.mux_grid VALUES ('193/107', '0106000020E6100000010000000103000000010000000500000011E724621A0954C0684D3458F2EF16C00E186F904DCD53C0C4A6D90C047F17C04D1E7236EED953C00E5DB3C45F141BC04EED2708BB1554C0B3030E104E851AC011E724621A0954C0684D3458F2EF16C0', 1698, 1698, 5219, -6.27210000000000001, -79.7287000000000035, 'S 06 16 19', 'O 79 43 43', 193, 107);
INSERT INTO bdc.mux_grid VALUES ('193/92', '0106000020E610000001000000010300000001000000050000005C8B973F7D4C53C0A6C4BFF090D21E406E6AC750B21053C009166ABF83431E409841D5085F1D53C09F33A3BE46AE1A408662A5F7295953C03CE2F8EF533D1B405C8B973F7D4C53C0A6C4BFF090D21E40', 1699, 1699, 5241, 7.16790000000000038, -76.7819999999999965, 'N 07 10 04', 'O 76 46 55', 193, 92);
INSERT INTO bdc.mux_grid VALUES ('193/93', '0106000020E610000001000000010300000001000000050000005C8C7576285953C0CCC86D56503D1B40480E9F3A5C1D53C0E29F580840AE1A40CAFD9CA1002A53C0A3A9994BED181740DE7B73DDCC6553C08DD2AE99FDA717405C8C7576285953C0CCC86D56503D1B40', 1700, 1700, 5244, 6.27210000000000001, -76.979699999999994, 'N 06 16 19', 'O 76 58 46', 193, 93);
INSERT INTO bdc.mux_grid VALUES ('193/99', '0106000020E61000000100000001030000000100000005000000160CEB54A7A453C04A06CC6FC2F1F63F161095DCD66853C000BE00AD58B5F43FA72A682F607553C0A93A4E30C47BD93FA726BEA730B153C0FBADBD9DB536E13F160CEB54A7A453C04A06CC6FC2F1F63F', 1701, 1701, 5251, 0.896100000000000008, -78.1584000000000003, 'N 00 53 45', 'O 78 09 30', 193, 99);
INSERT INTO bdc.mux_grid VALUES ('194/100', '0106000020E61000000100000001030000000100000005000000D8D6C16DF5EE53C0900D24BEB136E13F0A91C8D524B353C03DAC07B6B77BD93FBE1F385EADBF53C05259525307DEDFBF8C6531F67DFB53C095EA118D5BECD6BFD8D6C16DF5EE53C0900D24BEB136E13F', 1702, 1702, 5252, 0, -79.3192999999999984, 'N 00 00 00', 'O 79 19 09', 194, 100);
INSERT INTO bdc.mux_grid VALUES ('194/101', '0106000020E6100000010000000103000000010000000500000074B9EBF07DFB53C0C475E2565CECD6BFD2CB7D63ADBF53C08BCE818906DEDFBFE8970F2F36CC53C0F7FDAB51EE4DF6BF8A857DBC060854C0C62704C58311F4BF74B9EBF07DFB53C0C475E2565CECD6BF', 1703, 1703, 5254, -0.896100000000000008, -79.515199999999993, 'S 00 53 45', 'O 79 30 54', 194, 101);
INSERT INTO bdc.mux_grid VALUES ('194/102', '0106000020E61000000100000001030000000100000005000000AAABBEE5060854C0ECBC373A8211F4BFAEBD0F8D36CC53C091261ACEEA4DF6BF00506BA9C0D853C06B5B579B245202C0FA3D1A02911454C09D266651F03301C0AAABBEE5060854C0ECBC373A8211F4BF', 1704, 1704, 5255, -1.79220000000000002, -79.7111000000000018, 'S 01 47 31', 'O 79 42 39', 194, 102);
INSERT INTO bdc.mux_grid VALUES ('194/103', '0106000020E6100000010000000103000000010000000500000060CAF559911454C015FC01ADEE3301C080A55260C1D853C014A52930215202C00438C5DB4DE553C067F73AA7437D09C0E65C68D51D2154C0694E1324115F08C060CAF559911454C015FC01ADEE3301C0', 1705, 1705, 5257, -2.68829999999999991, -79.9070999999999998, 'S 02 41 17', 'O 79 54 25', 194, 103);
INSERT INTO bdc.mux_grid VALUES ('194/104', '0106000020E610000001000000010300000001000000050000003A11085C1E2154C09B61E99F0E5F08C08DD6EAEB4EE553C0B9B307913E7D09C054F0EBD5DEF153C03EF04658275410C0022B0946AE2D54C05E8E6FBF1E8A0FC03A11085C1E2154C09B61E99F0E5F08C0', 1706, 1706, 5258, -3.58429999999999982, -80.1033999999999935, 'S 03 35 03', 'O 80 06 12', 194, 104);
INSERT INTO bdc.mux_grid VALUES ('194/105', '0106000020E610000001000000010300000001000000050000005421ADFBAE2D54C097264D5A1B8A0FC02AADD13FE0F153C0FBE873F6235410C0A8F188A974FE53C060BDD50CA0E913C0D4656465433A54C0B16788C3895A13C05421ADFBAE2D54C097264D5A1B8A0FC0', 1707, 1707, 5259, -4.48029999999999973, -80.2998000000000047, 'S 04 28 49', 'O 80 17 59', 194, 105);
INSERT INTO bdc.mux_grid VALUES ('194/106', '0106000020E61000000100000001030000000100000005000000AC52634A443A54C00D86AB9F875A13C0AAE2DB6D76FE53C02237ABD29BE913C0609FA86A100B54C08BE66221097F17C0620F3047DE4654C0753563EEF4EF16C0AC52634A443A54C00D86AB9F875A13C0', 1708, 1708, 5260, -5.37619999999999987, -80.4966000000000008, 'S 05 22 34', 'O 80 29 47', 194, 106);


--
-- TOC entry 5588 (class 0 OID 2833998)
-- Dependencies: 230
-- Data for Name: providers; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5590 (class 0 OID 2834008)
-- Dependencies: 232
-- Data for Name: quicklook; Type: TABLE DATA; Schema: bdc; Owner: postgres
--



--
-- TOC entry 5591 (class 0 OID 2834013)
-- Dependencies: 233
-- Data for Name: resolution_unit; Type: TABLE DATA; Schema: bdc; Owner: postgres
--

INSERT INTO bdc.resolution_unit VALUES (1, 'micrometre', 'μm', NULL, '2020-12-01 13:47:34.418444+00', '2020-12-01 13:47:34.418444+00');


--
-- TOC entry 5593 (class 0 OID 2834023)
-- Dependencies: 235
-- Data for Name: tiles; Type: TABLE DATA; Schema: bdc; Owner: postgres
--

INSERT INTO bdc.tiles VALUES (1, 2, '188090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (2, 2, '147107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (3, 2, '147108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (4, 2, '147109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (5, 2, '147110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (6, 2, '147111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (7, 2, '148106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (8, 2, '148107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (9, 2, '148108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (10, 2, '148109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (11, 2, '148110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (12, 2, '148111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (13, 2, '148112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (14, 2, '149106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (15, 2, '149107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (16, 2, '149108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (17, 2, '149109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (18, 2, '149110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (19, 2, '149111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (20, 2, '149112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (21, 2, '149113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (22, 2, '149114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (23, 2, '149115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (24, 2, '149116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (25, 2, '149117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (26, 2, '149118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (27, 2, '149119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (28, 2, '149120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (29, 2, '149121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (30, 2, '149122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (31, 2, '150105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (32, 2, '150106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (33, 2, '150107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (34, 2, '150108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (35, 2, '150109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (36, 2, '150110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (37, 2, '150111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (38, 2, '150112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (39, 2, '150113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (40, 2, '150114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (41, 2, '150115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (42, 2, '150116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (43, 2, '150117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (44, 2, '150118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (45, 2, '150119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (46, 2, '150120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (47, 2, '150121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (48, 2, '150122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (49, 2, '150123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (50, 2, '150124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (51, 2, '150125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (52, 2, '151105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (53, 2, '151106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (54, 2, '151107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (55, 2, '151108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (56, 2, '151109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (57, 2, '151110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (58, 2, '151111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (59, 2, '151112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (60, 2, '151113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (61, 2, '151114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (62, 2, '151115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (63, 2, '151116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (64, 2, '151117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (65, 2, '151118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (66, 2, '151119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (67, 2, '151120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (68, 2, '151121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (69, 2, '151122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (70, 2, '151123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (71, 2, '151124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (72, 2, '151125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (73, 2, '152104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (74, 2, '152105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (75, 2, '152106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (76, 2, '152107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (77, 2, '152108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (78, 2, '152109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (79, 2, '152110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (80, 2, '152111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (81, 2, '152112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (82, 2, '152113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (83, 2, '152114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (84, 2, '152115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (85, 2, '152116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (86, 2, '152117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (87, 2, '152118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (88, 2, '152119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (89, 2, '152120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (90, 2, '152121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (91, 2, '152122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (92, 2, '152123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (93, 2, '152124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (94, 2, '152125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (95, 2, '153104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (96, 2, '153105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (97, 2, '153106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (98, 2, '153107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (99, 2, '153108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (100, 2, '153109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (101, 2, '153110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (102, 2, '153111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (103, 2, '153112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (104, 2, '153113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (105, 2, '153114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (106, 2, '153115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (107, 2, '153116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (108, 2, '153117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (109, 2, '153118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (110, 2, '153119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (111, 2, '153120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (112, 2, '153121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (113, 2, '153122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (114, 2, '153123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (115, 2, '153124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (116, 2, '153125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (117, 2, '153126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (118, 2, '154104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (119, 2, '154105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (120, 2, '154106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (121, 2, '154107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (122, 2, '154108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (123, 2, '154109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (124, 2, '154110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (125, 2, '154111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (126, 2, '154112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (127, 2, '154113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (128, 2, '154114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (129, 2, '154115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (130, 2, '154116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (131, 2, '154117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (132, 2, '154118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (133, 2, '154119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (134, 2, '154120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (135, 2, '154121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (136, 2, '154122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (137, 2, '154123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (138, 2, '154124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (139, 2, '154125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (140, 2, '154126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (141, 2, '155104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (142, 2, '155105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (143, 2, '155106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (144, 2, '155107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (145, 2, '155108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (146, 2, '155109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (147, 2, '155110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (148, 2, '155111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (149, 2, '155112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (150, 2, '155113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (151, 2, '155114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (152, 2, '155115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (153, 2, '155116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (154, 2, '155117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (155, 2, '155118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (156, 2, '155119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (157, 2, '155120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (158, 2, '155121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (159, 2, '155122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (160, 2, '155123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (161, 2, '155124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (162, 2, '155125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (163, 2, '155126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (164, 2, '155127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (165, 2, '156103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (166, 2, '156104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (167, 2, '156105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (168, 2, '156106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (169, 2, '156107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (170, 2, '156108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (171, 2, '156109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (172, 2, '156110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (173, 2, '156111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (174, 2, '156112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (175, 2, '156113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (176, 2, '156114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (177, 2, '156115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (178, 2, '156116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (179, 2, '156117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (180, 2, '156118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (181, 2, '156119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (182, 2, '156120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (183, 2, '156121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (184, 2, '156122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (185, 2, '156123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (186, 2, '156124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (187, 2, '156125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (188, 2, '156126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (189, 2, '156127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (190, 2, '156128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (191, 2, '156129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (192, 2, '156130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (193, 2, '156131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (194, 2, '156132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (195, 2, '157103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (196, 2, '157104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (197, 2, '157105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (198, 2, '157106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (199, 2, '157107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (200, 2, '157108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (201, 2, '157109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (202, 2, '157110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (203, 2, '157111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (204, 2, '157112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (205, 2, '157113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (206, 2, '157114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (207, 2, '157115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (208, 2, '157116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (209, 2, '157117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (210, 2, '157118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (211, 2, '157119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (212, 2, '157120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (213, 2, '157121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (214, 2, '157122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (215, 2, '157123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (216, 2, '157124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (217, 2, '157125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (218, 2, '157126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (219, 2, '157127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (220, 2, '157128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (221, 2, '157129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (222, 2, '157130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (223, 2, '157131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (224, 2, '157132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (225, 2, '157133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (226, 2, '158102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (227, 2, '158103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (228, 2, '158104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (229, 2, '158105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (230, 2, '158106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (231, 2, '158107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (232, 2, '158108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (233, 2, '158109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (234, 2, '158110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (235, 2, '158111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (236, 2, '158112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (237, 2, '158113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (238, 2, '158114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (239, 2, '158115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (240, 2, '158116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (241, 2, '158117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (242, 2, '158118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (243, 2, '158119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (244, 2, '158120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (245, 2, '158121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (246, 2, '158122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (247, 2, '158123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (248, 2, '158124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (249, 2, '158125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (250, 2, '158126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (251, 2, '158127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (252, 2, '158128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (253, 2, '158129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (254, 2, '158130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (255, 2, '158131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (256, 2, '158132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (257, 2, '158133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (258, 2, '158134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (259, 2, '158135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (260, 2, '159102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (261, 2, '159103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (262, 2, '159104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (263, 2, '159105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (264, 2, '159106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (265, 2, '159107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (266, 2, '159108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (267, 2, '159109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (268, 2, '159110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (269, 2, '159111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (270, 2, '159112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (271, 2, '159113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (272, 2, '159114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (273, 2, '159115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (274, 2, '159116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (275, 2, '159117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (276, 2, '159118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (277, 2, '159119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (278, 2, '159120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (279, 2, '159121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (280, 2, '159122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (281, 2, '159123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (282, 2, '159124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (283, 2, '159125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (284, 2, '159126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (285, 2, '159127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (286, 2, '159128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (287, 2, '159129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (288, 2, '159130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (289, 2, '159131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (290, 2, '159132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (291, 2, '159133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (292, 2, '159134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (293, 2, '159135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (294, 2, '159136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (295, 2, '159137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (296, 2, '160101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (297, 2, '160102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (298, 2, '160103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (299, 2, '160104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (300, 2, '160105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (301, 2, '160106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (302, 2, '160107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (303, 2, '160108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (304, 2, '160109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (305, 2, '160110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (306, 2, '160111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (307, 2, '160112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (308, 2, '160113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (309, 2, '160114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (310, 2, '160115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (311, 2, '160116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (312, 2, '160117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (313, 2, '160118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (314, 2, '160119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (315, 2, '160120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (316, 2, '160121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (317, 2, '160122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (318, 2, '160123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (319, 2, '160124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (320, 2, '160125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (321, 2, '160126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (322, 2, '160127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (323, 2, '160128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (324, 2, '160129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (325, 2, '160130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (326, 2, '160131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (327, 2, '160132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (328, 2, '160133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (329, 2, '160134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (330, 2, '160135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (331, 2, '160136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (332, 2, '160137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (333, 2, '160138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (334, 2, '161101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (335, 2, '161102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (336, 2, '161103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (337, 2, '161104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (338, 2, '161105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (339, 2, '161106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (340, 2, '161107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (341, 2, '161108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (342, 2, '161109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (343, 2, '161110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (344, 2, '161111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (345, 2, '161112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (346, 2, '161113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (347, 2, '161114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (348, 2, '161115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (349, 2, '161116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (350, 2, '161117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (351, 2, '161118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (352, 2, '161119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (353, 2, '161120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (354, 2, '161121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (355, 2, '161122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (356, 2, '161123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (357, 2, '161124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (358, 2, '161125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (359, 2, '161126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (360, 2, '161127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (361, 2, '161128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (362, 2, '161129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (363, 2, '161130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (364, 2, '161131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (365, 2, '161132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (366, 2, '161133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (367, 2, '161134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (368, 2, '161135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (369, 2, '161136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (370, 2, '161137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (371, 2, '161138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (372, 2, '162102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (373, 2, '162103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (374, 2, '162104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (375, 2, '162105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (376, 2, '162106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (377, 2, '162107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (378, 2, '162108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (379, 2, '162109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (380, 2, '162110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (381, 2, '162111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (382, 2, '162112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (383, 2, '162113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (384, 2, '162114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (385, 2, '162115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (386, 2, '162116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (387, 2, '162117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (388, 2, '162118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (389, 2, '162119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (390, 2, '162120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (391, 2, '162121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (392, 2, '162122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (393, 2, '162123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (394, 2, '162124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (395, 2, '162125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (396, 2, '162126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (397, 2, '162127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (398, 2, '162128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (399, 2, '162129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (400, 2, '162130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (401, 2, '162131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (402, 2, '162132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (403, 2, '162133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (404, 2, '162134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (405, 2, '162135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (406, 2, '162136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (407, 2, '162137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (408, 2, '162138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (409, 2, '162141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (410, 2, '162142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (411, 2, '163101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (412, 2, '163102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (413, 2, '163103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (414, 2, '163104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (415, 2, '163105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (416, 2, '163106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (417, 2, '163107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (418, 2, '163108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (419, 2, '163109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (420, 2, '163110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (421, 2, '163111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (422, 2, '163112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (423, 2, '163113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (424, 2, '163114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (425, 2, '163115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (426, 2, '163116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (427, 2, '163117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (428, 2, '163118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (429, 2, '163119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (430, 2, '163120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (431, 2, '163121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (432, 2, '163122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (433, 2, '163123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (434, 2, '163124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (435, 2, '163125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (436, 2, '163126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (437, 2, '163127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (438, 2, '163128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (439, 2, '163129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (440, 2, '163130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (441, 2, '163131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (442, 2, '163132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (443, 2, '163133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (444, 2, '163134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (445, 2, '163135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (446, 2, '163136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (447, 2, '163137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (448, 2, '163138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (449, 2, '163140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (450, 2, '163141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (451, 2, '163142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (452, 2, '163143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (453, 2, '164101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (454, 2, '164102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (455, 2, '164103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (456, 2, '164104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (457, 2, '164105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (458, 2, '164106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (459, 2, '164107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (460, 2, '164108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (461, 2, '164109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (462, 2, '164110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (463, 2, '164111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (464, 2, '164112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (465, 2, '164113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (466, 2, '164114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (467, 2, '164115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (468, 2, '164116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (469, 2, '164117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (470, 2, '164118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (471, 2, '164119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (472, 2, '164120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (473, 2, '164121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (474, 2, '164122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (475, 2, '164123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (476, 2, '164124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (477, 2, '164125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (478, 2, '164126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (479, 2, '164127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (480, 2, '164128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (481, 2, '164129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (482, 2, '164130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (483, 2, '164131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (484, 2, '164132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (485, 2, '164133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (486, 2, '164134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (487, 2, '164135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (488, 2, '164136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (489, 2, '164137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (490, 2, '164138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (491, 2, '164139', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (492, 2, '164140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (493, 2, '164141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (494, 2, '164142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (495, 2, '164143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (496, 2, '164099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (497, 2, '165100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (498, 2, '165101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (499, 2, '165102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (500, 2, '165103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (501, 2, '165104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (502, 2, '165105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (503, 2, '165106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (504, 2, '165107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (505, 2, '165108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (506, 2, '165109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (507, 2, '165110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (508, 2, '165111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (509, 2, '165112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (510, 2, '165113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (511, 2, '165114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (512, 2, '165115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (513, 2, '165116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (514, 2, '165117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (515, 2, '165118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (516, 2, '165119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (517, 2, '165120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (518, 2, '165121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (519, 2, '165122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (520, 2, '165123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (521, 2, '165124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (522, 2, '165125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (523, 2, '165126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (524, 2, '165127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (525, 2, '165128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (526, 2, '165129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (527, 2, '165130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (528, 2, '165131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (529, 2, '165132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (530, 2, '165133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (531, 2, '165134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (532, 2, '165135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (533, 2, '165136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (534, 2, '165137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (535, 2, '165138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (536, 2, '165139', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (537, 2, '165140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (538, 2, '165141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (539, 2, '165142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (540, 2, '165143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (541, 2, '165097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (542, 2, '165098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (543, 2, '165099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (544, 2, '166100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (545, 2, '166101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (546, 2, '166102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (547, 2, '166103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (548, 2, '166104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (549, 2, '166105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (550, 2, '166106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (551, 2, '166107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (552, 2, '166108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (553, 2, '166109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (554, 2, '166110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (555, 2, '166111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (556, 2, '166112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (557, 2, '166113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (558, 2, '166114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (559, 2, '166115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (560, 2, '166116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (561, 2, '166117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (562, 2, '166118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (563, 2, '166119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (564, 2, '166120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (565, 2, '166121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (566, 2, '166122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (567, 2, '166123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (568, 2, '166124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (569, 2, '166125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (570, 2, '166126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (571, 2, '166127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (572, 2, '166128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (573, 2, '166129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (574, 2, '166130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (575, 2, '166131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (576, 2, '166132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (577, 2, '166133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (578, 2, '166134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (579, 2, '166135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (580, 2, '166136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (581, 2, '166137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (582, 2, '166138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (583, 2, '166139', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (584, 2, '166140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (585, 2, '166141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (586, 2, '166142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (587, 2, '166143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (588, 2, '166096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (589, 2, '166097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (590, 2, '166098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (591, 2, '166099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (592, 2, '167100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (593, 2, '167101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (594, 2, '167102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (595, 2, '167103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (596, 2, '167104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (597, 2, '167105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (598, 2, '167106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (599, 2, '167107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (600, 2, '167108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (601, 2, '167109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (602, 2, '167110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (603, 2, '167111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (604, 2, '167112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (605, 2, '167113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (606, 2, '167114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (607, 2, '167115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (608, 2, '167116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (609, 2, '167117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (610, 2, '167118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (611, 2, '167119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (612, 2, '167120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (613, 2, '167121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (614, 2, '167122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (615, 2, '167123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (616, 2, '167124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (617, 2, '167125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (618, 2, '167126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (619, 2, '167127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (620, 2, '167128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (621, 2, '167129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (622, 2, '167130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (623, 2, '167131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (624, 2, '167132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (625, 2, '167133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (626, 2, '167134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (627, 2, '167135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (628, 2, '167136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (629, 2, '167137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (630, 2, '167138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (631, 2, '167139', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (632, 2, '167140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (633, 2, '167141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (634, 2, '167142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (635, 2, '167143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (636, 2, '167144', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (637, 2, '167145', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (638, 2, '167095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (639, 2, '167096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (640, 2, '167097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (641, 2, '167098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (642, 2, '167099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (643, 2, '168100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (644, 2, '168101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (645, 2, '168102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (646, 2, '168103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (647, 2, '168104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (648, 2, '168105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (649, 2, '168106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (650, 2, '168107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (651, 2, '168108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (652, 2, '168109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (653, 2, '168110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (654, 2, '168111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (655, 2, '168112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (656, 2, '168113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (657, 2, '168114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (658, 2, '168115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (659, 2, '168116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (660, 2, '168117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (661, 2, '168118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (662, 2, '168119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (663, 2, '168120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (664, 2, '168121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (665, 2, '168122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (666, 2, '168123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (667, 2, '168124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (668, 2, '168125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (669, 2, '168126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (670, 2, '168127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (671, 2, '168128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (672, 2, '168129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (673, 2, '168130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (674, 2, '168131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (675, 2, '168132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (676, 2, '168133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (677, 2, '168134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (678, 2, '168135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (679, 2, '168136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (680, 2, '168137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (681, 2, '168138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (682, 2, '168139', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (683, 2, '168140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (684, 2, '168141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (685, 2, '168142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (686, 2, '168143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (687, 2, '168144', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (688, 2, '168145', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (689, 2, '168148', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (690, 2, '168149', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (691, 2, '168150', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (692, 2, '168153', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (693, 2, '168154', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (694, 2, '168155', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (695, 2, '168156', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (696, 2, '168094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (697, 2, '168095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (698, 2, '168096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (699, 2, '168097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (700, 2, '168098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (701, 2, '168099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (702, 2, '169100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (703, 2, '169101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (704, 2, '169102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (705, 2, '169103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (706, 2, '169104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (707, 2, '169105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (708, 2, '169106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (709, 2, '169107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (710, 2, '169108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (711, 2, '169109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (712, 2, '169110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (713, 2, '169111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (714, 2, '169112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (715, 2, '169113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (716, 2, '169114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (717, 2, '169115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (718, 2, '169116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (719, 2, '169117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (720, 2, '169118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (721, 2, '169119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (722, 2, '169120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (723, 2, '169121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (724, 2, '169122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (725, 2, '169123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (726, 2, '169124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (727, 2, '169125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (728, 2, '169126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (729, 2, '169127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (730, 2, '169128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (731, 2, '169129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (732, 2, '169130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (733, 2, '169131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (734, 2, '169132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (735, 2, '169133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (736, 2, '169134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (737, 2, '169135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (738, 2, '169136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (739, 2, '169137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (740, 2, '169138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (741, 2, '169139', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (742, 2, '169140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (743, 2, '169141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (744, 2, '169142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (745, 2, '169143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (746, 2, '169144', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (747, 2, '169145', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (748, 2, '169146', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (749, 2, '169147', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (750, 2, '169148', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (751, 2, '169149', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (752, 2, '169150', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (753, 2, '169151', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (754, 2, '169152', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (755, 2, '169153', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (756, 2, '169154', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (757, 2, '169155', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (758, 2, '169156', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (759, 2, '169157', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (760, 2, '169158', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (761, 2, '169094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (762, 2, '169095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (763, 2, '169096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (764, 2, '169097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (765, 2, '169098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (766, 2, '169099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (767, 2, '170100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (768, 2, '170101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (769, 2, '170102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (770, 2, '170103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (771, 2, '170104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (772, 2, '170105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (773, 2, '170106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (774, 2, '170107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (775, 2, '170108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (776, 2, '170109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (777, 2, '170110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (778, 2, '170111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (779, 2, '170112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (780, 2, '170113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (781, 2, '170114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (782, 2, '170115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (783, 2, '170116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (784, 2, '170117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (785, 2, '170118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (786, 2, '170119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (787, 2, '170120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (788, 2, '170121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (789, 2, '170122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (790, 2, '170123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (791, 2, '170124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (792, 2, '170125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (793, 2, '170126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (794, 2, '170127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (795, 2, '170128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (796, 2, '170129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (797, 2, '170130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (798, 2, '170131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (799, 2, '170132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (800, 2, '170133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (801, 2, '170134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (802, 2, '170135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (803, 2, '170136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (804, 2, '170137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (805, 2, '170138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (806, 2, '170139', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (807, 2, '170140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (808, 2, '170141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (809, 2, '170142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (810, 2, '170143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (811, 2, '170144', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (812, 2, '170145', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (813, 2, '170146', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (814, 2, '170147', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (815, 2, '170148', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (816, 2, '170149', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (817, 2, '170150', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (818, 2, '170151', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (819, 2, '170152', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (820, 2, '170153', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (821, 2, '170154', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (822, 2, '170155', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (823, 2, '170156', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (824, 2, '170157', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (825, 2, '170158', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (826, 2, '170159', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (827, 2, '170094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (828, 2, '170095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (829, 2, '170096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (830, 2, '170097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (831, 2, '170098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (832, 2, '170099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (833, 2, '171100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (834, 2, '171101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (835, 2, '171102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (836, 2, '171103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (837, 2, '171104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (838, 2, '171105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (839, 2, '171106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (840, 2, '171107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (841, 2, '171108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (842, 2, '171109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (843, 2, '171110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (844, 2, '171111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (845, 2, '171112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (846, 2, '171113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (847, 2, '171114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (848, 2, '171115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (849, 2, '171116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (850, 2, '171117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (851, 2, '171118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (852, 2, '171119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (853, 2, '171120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (854, 2, '171121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (855, 2, '171122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (856, 2, '171123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (857, 2, '171124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (858, 2, '171125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (859, 2, '171126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (860, 2, '171127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (861, 2, '171128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (862, 2, '171129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (863, 2, '171130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (864, 2, '171131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (865, 2, '171132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (866, 2, '171133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (867, 2, '171134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (868, 2, '171135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (869, 2, '171136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (870, 2, '171137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (871, 2, '171138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (872, 2, '171139', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (873, 2, '171140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (874, 2, '171141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (875, 2, '171142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (876, 2, '171143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (877, 2, '171144', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (878, 2, '171145', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (879, 2, '171146', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (880, 2, '171147', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (881, 2, '171148', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (882, 2, '171149', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (883, 2, '171150', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (884, 2, '171151', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (885, 2, '171152', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (886, 2, '171153', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (887, 2, '171154', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (888, 2, '171155', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (889, 2, '171156', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (890, 2, '171157', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (891, 2, '171158', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (892, 2, '171094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (893, 2, '171095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (894, 2, '171096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (895, 2, '171097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (896, 2, '171098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (897, 2, '171099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (898, 2, '172100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (899, 2, '172101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (900, 2, '172102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (901, 2, '172103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (902, 2, '172104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (903, 2, '172105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (904, 2, '172106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (905, 2, '172107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (906, 2, '172108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (907, 2, '172109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (908, 2, '172110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (909, 2, '172111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (910, 2, '172112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (911, 2, '172113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (912, 2, '172114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (913, 2, '172115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (914, 2, '172116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (915, 2, '172117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (916, 2, '172118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (917, 2, '172119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (918, 2, '172120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (919, 2, '172121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (920, 2, '172122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (921, 2, '172123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (922, 2, '172124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (923, 2, '172125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (924, 2, '172126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (925, 2, '172127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (926, 2, '172128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (927, 2, '172129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (928, 2, '172130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (929, 2, '172131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (930, 2, '172132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (931, 2, '172133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (932, 2, '172134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (933, 2, '172135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (934, 2, '172136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (935, 2, '172137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (936, 2, '172138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (937, 2, '172139', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (938, 2, '172140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (939, 2, '172141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (940, 2, '172142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (941, 2, '172143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (942, 2, '172144', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (943, 2, '172145', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (944, 2, '172146', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (945, 2, '172147', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (946, 2, '172148', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (947, 2, '172149', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (948, 2, '172150', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (949, 2, '172151', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (950, 2, '172152', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (951, 2, '172153', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (952, 2, '172154', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (953, 2, '172155', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (954, 2, '172156', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (955, 2, '172157', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (956, 2, '172094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (957, 2, '172095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (958, 2, '172096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (959, 2, '172097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (960, 2, '172098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (961, 2, '172099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (962, 2, '173100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (963, 2, '173101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (964, 2, '173102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (965, 2, '173103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (966, 2, '173104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (967, 2, '173105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (968, 2, '173106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (969, 2, '173107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (970, 2, '173108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (971, 2, '173109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (972, 2, '173110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (973, 2, '173111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (974, 2, '173112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (975, 2, '173113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (976, 2, '173114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (977, 2, '173115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (978, 2, '173116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (979, 2, '173117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (980, 2, '173118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (981, 2, '173119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (982, 2, '173120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (983, 2, '173121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (984, 2, '173122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (985, 2, '173123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (986, 2, '173124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (987, 2, '173125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (988, 2, '173126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (989, 2, '173127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (990, 2, '173128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (991, 2, '173129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (992, 2, '173130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (993, 2, '173131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (994, 2, '173132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (995, 2, '173133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (996, 2, '173134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (997, 2, '173135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (998, 2, '173136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (999, 2, '173137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1000, 2, '173138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1001, 2, '173139', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1002, 2, '173140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1003, 2, '173141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1004, 2, '173142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1005, 2, '173143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1006, 2, '173144', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1007, 2, '173145', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1008, 2, '173146', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1009, 2, '173147', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1010, 2, '173148', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1011, 2, '173149', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1012, 2, '173150', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1013, 2, '173151', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1014, 2, '173152', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1015, 2, '173093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1016, 2, '173094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1017, 2, '173095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1018, 2, '173096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1019, 2, '173097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1020, 2, '173098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1021, 2, '173099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1022, 2, '174100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1023, 2, '174101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1024, 2, '174102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1025, 2, '174103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1026, 2, '174104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1027, 2, '174105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1028, 2, '174106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1029, 2, '174107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1030, 2, '174108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1031, 2, '174109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1032, 2, '174110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1033, 2, '174111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1034, 2, '174112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1035, 2, '174113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1036, 2, '174114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1037, 2, '174115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1038, 2, '174116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1039, 2, '174117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1040, 2, '174118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1041, 2, '174119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1042, 2, '174120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1043, 2, '174121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1044, 2, '174122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1045, 2, '174123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1046, 2, '174124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1047, 2, '174125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1048, 2, '174126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1049, 2, '174127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1050, 2, '174128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1051, 2, '174129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1052, 2, '174130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1053, 2, '174131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1054, 2, '174132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1055, 2, '174133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1056, 2, '174134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1057, 2, '174135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1058, 2, '174136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1059, 2, '174137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1060, 2, '174138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1061, 2, '174139', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1062, 2, '174140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1063, 2, '174141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1064, 2, '174142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1065, 2, '174143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1066, 2, '174144', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1067, 2, '174145', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1068, 2, '174146', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1069, 2, '174147', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1070, 2, '174148', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1071, 2, '174149', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1072, 2, '174150', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1073, 2, '174151', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1074, 2, '174093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1075, 2, '174094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1076, 2, '174095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1077, 2, '174096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1078, 2, '174097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1079, 2, '174098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1080, 2, '174099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1081, 2, '175100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1082, 2, '175101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1083, 2, '175102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1084, 2, '175103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1085, 2, '175104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1086, 2, '175105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1087, 2, '175106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1088, 2, '175107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1089, 2, '175108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1090, 2, '175109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1091, 2, '175110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1092, 2, '175111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1093, 2, '175112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1094, 2, '175113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1095, 2, '175114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1096, 2, '175115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1097, 2, '175116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1098, 2, '175117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1099, 2, '175118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1100, 2, '175119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1101, 2, '175120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1102, 2, '175121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1103, 2, '175122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1104, 2, '175123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1105, 2, '175124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1106, 2, '175125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1107, 2, '175126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1108, 2, '175127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1109, 2, '175128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1110, 2, '175129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1111, 2, '175130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1112, 2, '175131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1113, 2, '175132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1114, 2, '175133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1115, 2, '175134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1116, 2, '175135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1117, 2, '175136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1118, 2, '175137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1119, 2, '175138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1120, 2, '175139', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1121, 2, '175140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1122, 2, '175141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1123, 2, '175142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1124, 2, '175143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1125, 2, '175144', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1126, 2, '175145', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1127, 2, '175146', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1128, 2, '175147', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1129, 2, '175148', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1130, 2, '175091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1131, 2, '175092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1132, 2, '175093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1133, 2, '175094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1134, 2, '175095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1135, 2, '175096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1136, 2, '175097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1137, 2, '175098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1138, 2, '175099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1139, 2, '176100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1140, 2, '176101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1141, 2, '176102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1142, 2, '176103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1143, 2, '176104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1144, 2, '176105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1145, 2, '176106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1146, 2, '176107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1147, 2, '176108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1148, 2, '176109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1149, 2, '176110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1150, 2, '176111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1151, 2, '176112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1152, 2, '176113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1153, 2, '176114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1154, 2, '176115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1155, 2, '176116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1156, 2, '176117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1157, 2, '176118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1158, 2, '176119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1159, 2, '176120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1160, 2, '176121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1161, 2, '176122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1162, 2, '176123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1163, 2, '176124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1164, 2, '176125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1165, 2, '176126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1166, 2, '176127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1167, 2, '176128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1168, 2, '176129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1169, 2, '176130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1170, 2, '176131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1171, 2, '176132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1172, 2, '176133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1173, 2, '176134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1174, 2, '176135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1175, 2, '176136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1176, 2, '176137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1177, 2, '176138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1178, 2, '176139', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1179, 2, '176140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1180, 2, '176141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1181, 2, '176142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1182, 2, '176143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1183, 2, '176144', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1184, 2, '176145', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1185, 2, '176091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1186, 2, '176092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1187, 2, '176093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1188, 2, '176094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1189, 2, '176095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1190, 2, '176096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1191, 2, '176097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1192, 2, '176098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1193, 2, '176099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1194, 2, '177100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1195, 2, '177101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1196, 2, '177102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1197, 2, '177103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1198, 2, '177104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1199, 2, '177105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1200, 2, '177106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1201, 2, '177107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1202, 2, '177108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1203, 2, '177109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1204, 2, '177110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1205, 2, '177111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1206, 2, '177112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1207, 2, '177113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1208, 2, '177114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1209, 2, '177115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1210, 2, '177116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1211, 2, '177117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1212, 2, '177118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1213, 2, '177119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1214, 2, '177120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1215, 2, '177121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1216, 2, '177122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1217, 2, '177123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1218, 2, '177124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1219, 2, '177125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1220, 2, '177126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1221, 2, '177127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1222, 2, '177128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1223, 2, '177129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1224, 2, '177130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1225, 2, '177131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1226, 2, '177132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1227, 2, '177133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1228, 2, '177134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1229, 2, '177135', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1230, 2, '177136', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1231, 2, '177137', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1232, 2, '177138', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1233, 2, '177139', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1234, 2, '177140', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1235, 2, '177141', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1236, 2, '177142', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1237, 2, '177143', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1238, 2, '177144', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1239, 2, '177091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1240, 2, '177092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1241, 2, '177093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1242, 2, '177094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1243, 2, '177095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1244, 2, '177096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1245, 2, '177097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1246, 2, '177098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1247, 2, '177099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1248, 2, '178100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1249, 2, '178101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1250, 2, '178102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1251, 2, '178103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1252, 2, '178104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1253, 2, '178105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1254, 2, '178106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1255, 2, '178107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1256, 2, '178108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1257, 2, '178109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1258, 2, '178110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1259, 2, '178111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1260, 2, '178112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1261, 2, '178113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1262, 2, '178114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1263, 2, '178115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1264, 2, '178116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1265, 2, '178117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1266, 2, '178118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1267, 2, '178119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1268, 2, '178120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1269, 2, '178121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1270, 2, '178122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1271, 2, '178123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1272, 2, '178124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1273, 2, '178125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1274, 2, '178126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1275, 2, '178127', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1276, 2, '178128', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1277, 2, '178129', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1278, 2, '178130', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1279, 2, '178131', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1280, 2, '178132', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1281, 2, '178133', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1282, 2, '178134', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1283, 2, '178090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1284, 2, '178091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1285, 2, '178092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1286, 2, '178093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1287, 2, '178094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1288, 2, '178095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1289, 2, '178096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1290, 2, '178097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1291, 2, '178098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1292, 2, '178099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1293, 2, '179100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1294, 2, '179101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1295, 2, '179102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1296, 2, '179103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1297, 2, '179104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1298, 2, '179105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1299, 2, '179106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1300, 2, '179107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1301, 2, '179108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1302, 2, '179109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1303, 2, '179110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1304, 2, '179111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1305, 2, '179112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1306, 2, '179113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1307, 2, '179114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1308, 2, '179115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1309, 2, '179116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1310, 2, '179117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1311, 2, '179118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1312, 2, '179119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1313, 2, '179120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1314, 2, '179121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1315, 2, '179122', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1316, 2, '179123', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1317, 2, '179124', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1318, 2, '179125', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1319, 2, '179126', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1320, 2, '179089', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1321, 2, '179090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1322, 2, '179091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1323, 2, '179092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1324, 2, '179093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1325, 2, '179094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1326, 2, '179095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1327, 2, '179096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1328, 2, '179097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1329, 2, '179098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1330, 2, '179099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1331, 2, '180100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1332, 2, '180101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1333, 2, '180102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1334, 2, '180103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1335, 2, '180104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1336, 2, '180105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1337, 2, '180106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1338, 2, '180107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1339, 2, '180108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1340, 2, '180109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1341, 2, '180110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1342, 2, '180111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1343, 2, '180112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1344, 2, '180113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1345, 2, '180114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1346, 2, '180115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1347, 2, '180116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1348, 2, '180117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1349, 2, '180118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1350, 2, '180119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1351, 2, '180120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1352, 2, '180121', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1353, 2, '180089', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1354, 2, '180090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1355, 2, '180091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1356, 2, '180092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1357, 2, '180093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1358, 2, '180094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1359, 2, '180095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1360, 2, '180096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1361, 2, '180097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1362, 2, '180098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1363, 2, '180099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1364, 2, '181100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1365, 2, '181101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1366, 2, '181102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1367, 2, '181103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1368, 2, '181104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1369, 2, '181105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1370, 2, '181106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1371, 2, '181107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1372, 2, '181108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1373, 2, '181109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1374, 2, '181110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1375, 2, '181111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1376, 2, '181112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1377, 2, '181113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1378, 2, '181114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1379, 2, '181115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1380, 2, '181116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1381, 2, '181117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1382, 2, '181118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1383, 2, '181119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1384, 2, '181120', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1385, 2, '181089', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1386, 2, '181090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1387, 2, '181091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1388, 2, '181092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1389, 2, '181093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1390, 2, '181094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1391, 2, '181095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1392, 2, '181096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1393, 2, '181097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1394, 2, '181098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1395, 2, '181099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1396, 2, '182100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1397, 2, '182101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1398, 2, '182102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1399, 2, '182103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1400, 2, '182104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1401, 2, '182105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1402, 2, '182106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1403, 2, '182107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1404, 2, '182108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1405, 2, '182109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1406, 2, '182110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1407, 2, '182111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1408, 2, '182112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1409, 2, '182113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1410, 2, '182114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1411, 2, '182115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1412, 2, '182116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1413, 2, '182117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1414, 2, '182118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1415, 2, '182119', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1416, 2, '182089', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1417, 2, '182090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1418, 2, '182091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1419, 2, '182092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1420, 2, '182093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1421, 2, '182094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1422, 2, '182095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1423, 2, '182096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1424, 2, '182097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1425, 2, '182098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1426, 2, '182099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1427, 2, '183100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1428, 2, '183101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1429, 2, '183102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1430, 2, '183103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1431, 2, '183104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1432, 2, '183105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1433, 2, '183106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1434, 2, '183107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1435, 2, '183108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1436, 2, '183109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1437, 2, '183110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1438, 2, '183111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1439, 2, '183112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1440, 2, '183113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1441, 2, '183114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1442, 2, '183115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1443, 2, '183116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1444, 2, '183117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1445, 2, '183118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1446, 2, '183089', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1447, 2, '183090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1448, 2, '183091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1449, 2, '183092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1450, 2, '183093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1451, 2, '183094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1452, 2, '183095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1453, 2, '183096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1454, 2, '183097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1455, 2, '183098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1456, 2, '183099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1457, 2, '184100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1458, 2, '184101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1459, 2, '184102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1460, 2, '184103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1461, 2, '184104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1462, 2, '184105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1463, 2, '184106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1464, 2, '184107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1465, 2, '184108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1466, 2, '184109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1467, 2, '184110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1468, 2, '184111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1469, 2, '184112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1470, 2, '184113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1471, 2, '184114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1472, 2, '184115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1473, 2, '184116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1474, 2, '184117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1475, 2, '184118', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1476, 2, '184089', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1477, 2, '184090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1478, 2, '184091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1479, 2, '184092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1480, 2, '184093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1481, 2, '184094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1482, 2, '184095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1483, 2, '184096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1484, 2, '184097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1485, 2, '184098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1486, 2, '184099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1487, 2, '185100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1488, 2, '185101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1489, 2, '185102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1490, 2, '185103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1491, 2, '185104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1492, 2, '185105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1493, 2, '185106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1494, 2, '185107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1495, 2, '185108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1496, 2, '185109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1497, 2, '185110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1498, 2, '185111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1499, 2, '185112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1500, 2, '185113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1501, 2, '185114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1502, 2, '185115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1503, 2, '185116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1504, 2, '185117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1505, 2, '185089', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1506, 2, '185090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1507, 2, '185091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1508, 2, '185092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1509, 2, '185093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1510, 2, '185094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1511, 2, '185095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1512, 2, '185096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1513, 2, '185097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1514, 2, '185098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1515, 2, '185099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1516, 2, '186100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1517, 2, '186101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1518, 2, '186102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1519, 2, '186103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1520, 2, '186104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1521, 2, '186105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1522, 2, '186106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1523, 2, '186107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1524, 2, '186108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1525, 2, '186109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1526, 2, '186110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1527, 2, '186111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1528, 2, '186112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1529, 2, '186113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1530, 2, '186114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1531, 2, '186115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1532, 2, '186116', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1533, 2, '186117', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1534, 2, '186088', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1535, 2, '186089', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1536, 2, '186090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1537, 2, '186091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1538, 2, '186092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1539, 2, '186093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1540, 2, '186094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1541, 2, '186095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1542, 2, '186096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1543, 2, '186097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1544, 2, '186098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1545, 2, '186099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1546, 2, '187100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1547, 2, '187101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1548, 2, '187102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1549, 2, '187103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1550, 2, '187104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1551, 2, '187105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1552, 2, '187106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1553, 2, '187107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1554, 2, '187108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1555, 2, '187109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1556, 2, '187110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1557, 2, '187111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1558, 2, '187112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1559, 2, '187113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1560, 2, '187114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1561, 2, '187115', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1562, 2, '187088', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1563, 2, '187089', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1564, 2, '187090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1565, 2, '187091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1566, 2, '187092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1567, 2, '187093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1568, 2, '187094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1569, 2, '187095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1570, 2, '187096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1571, 2, '187097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1572, 2, '187098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1573, 2, '187099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1574, 2, '188100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1575, 2, '188101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1576, 2, '188102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1577, 2, '188103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1578, 2, '188104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1579, 2, '188105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1580, 2, '188106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1581, 2, '188107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1582, 2, '188108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1583, 2, '188109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1584, 2, '188110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1585, 2, '188111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1586, 2, '188112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1587, 2, '188113', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1588, 2, '188114', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1589, 2, '188089', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1590, 2, '188091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1591, 2, '188092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1592, 2, '188093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1593, 2, '188094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1594, 2, '188095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1595, 2, '188096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1596, 2, '188097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1597, 2, '188098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1598, 2, '188099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1599, 2, '189100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1600, 2, '189101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1601, 2, '189102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1602, 2, '189103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1603, 2, '189104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1604, 2, '189105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1605, 2, '189106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1606, 2, '189107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1607, 2, '189108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1608, 2, '189109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1609, 2, '189110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1610, 2, '189111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1611, 2, '189112', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1612, 2, '189087', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1613, 2, '189088', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1614, 2, '189089', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1615, 2, '189090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1616, 2, '189091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1617, 2, '189092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1618, 2, '189093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1619, 2, '189094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1620, 2, '189095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1621, 2, '189096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1622, 2, '189097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1623, 2, '189098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1624, 2, '189099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1625, 2, '190100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1626, 2, '190101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1627, 2, '190102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1628, 2, '190103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1629, 2, '190104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1630, 2, '190105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1631, 2, '190106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1632, 2, '190107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1633, 2, '190108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1634, 2, '190109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1635, 2, '190110', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1636, 2, '190111', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1637, 2, '190088', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1638, 2, '190089', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1639, 2, '190090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1640, 2, '190091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1641, 2, '190092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1642, 2, '190093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1643, 2, '190094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1644, 2, '190095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1645, 2, '190096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1646, 2, '190097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1647, 2, '190098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1648, 2, '190099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1649, 2, '191100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1650, 2, '191101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1651, 2, '191102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1652, 2, '191103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1653, 2, '191104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1654, 2, '191105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1655, 2, '191106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1656, 2, '191107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1657, 2, '191108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1658, 2, '191109', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1659, 2, '191088', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1660, 2, '191089', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1661, 2, '191090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1662, 2, '191091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1663, 2, '191092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1664, 2, '191093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1665, 2, '191094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1666, 2, '191095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1667, 2, '191096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1668, 2, '191097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1669, 2, '191098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1670, 2, '191099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1671, 2, '192100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1672, 2, '192101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1673, 2, '192102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1674, 2, '192103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1675, 2, '192104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1676, 2, '192105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1677, 2, '192106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1678, 2, '192107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1679, 2, '192108', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1680, 2, '192089', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1681, 2, '192090', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1682, 2, '192091', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1683, 2, '192092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1684, 2, '192093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1685, 2, '192094', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1686, 2, '192095', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1687, 2, '192096', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1688, 2, '192097', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1689, 2, '192098', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1690, 2, '192099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1691, 2, '193100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1692, 2, '193101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1693, 2, '193102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1694, 2, '193103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1695, 2, '193104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1696, 2, '193105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1697, 2, '193106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1698, 2, '193107', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1699, 2, '193092', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1700, 2, '193093', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1701, 2, '193099', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1702, 2, '194100', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1703, 2, '194101', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1704, 2, '194102', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1705, 2, '194103', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1706, 2, '194104', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1707, 2, '194105', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');
INSERT INTO bdc.tiles VALUES (1708, 2, '194106', '2020-11-03 19:21:19.937283+00', '2020-11-03 19:21:19.937283+00');


--
-- TOC entry 5595 (class 0 OID 2834030)
-- Dependencies: 237
-- Data for Name: timeline; Type: TABLE DATA; Schema: bdc; Owner: postgres
--

INSERT INTO bdc.timeline VALUES (28, '2020-07-31 13:08:34+00', '2021-05-06 16:57:32.05378+00', '2021-05-06 16:57:32.05378+00');
INSERT INTO bdc.timeline VALUES (26, '2018-01-01 13:15:18+00', '2021-05-06 16:57:32.05378+00', '2021-05-06 16:57:32.05378+00');
INSERT INTO bdc.timeline VALUES (28, '2018-01-01 13:15:18+00', '2021-05-06 16:57:32.05378+00', '2021-05-06 16:57:32.05378+00');
INSERT INTO bdc.timeline VALUES (24, '2020-12-28 13:27:20+00', '2021-05-06 16:57:32.05378+00', '2021-05-06 16:57:32.05378+00');
INSERT INTO bdc.timeline VALUES (33, '2021-02-01 08:09:34+00', '2021-05-06 16:57:32.05378+00', '2021-05-06 16:57:32.05378+00');
INSERT INTO bdc.timeline VALUES (22, '2021-02-01 13:11:48+00', '2021-05-06 16:57:32.05378+00', '2021-05-06 16:57:32.05378+00');
INSERT INTO bdc.timeline VALUES (24, '2021-02-01 13:11:48+00', '2021-05-06 16:57:32.05378+00', '2021-05-06 16:57:32.05378+00');
INSERT INTO bdc.timeline VALUES (37, '2021-03-03 12:57:42+00', '2021-05-06 16:57:33.355353+00', '2021-05-06 16:57:33.355353+00');
INSERT INTO bdc.timeline VALUES (37, '2021-03-03 14:40:46+00', '2021-05-06 16:57:33.355353+00', '2021-05-06 16:57:33.355353+00');
INSERT INTO bdc.timeline VALUES (13, '2010-03-01 13:10:12+00', '2021-05-06 16:57:36.762586+00', '2021-05-06 16:57:36.762586+00');
INSERT INTO bdc.timeline VALUES (14, '2010-03-01 13:21:01+00', '2021-05-06 16:57:36.762586+00', '2021-05-06 16:57:36.762586+00');
INSERT INTO bdc.timeline VALUES (14, '2010-03-01 13:20:58+00', '2021-05-06 16:57:36.762586+00', '2021-05-06 16:57:36.762586+00');
INSERT INTO bdc.timeline VALUES (15, '2010-03-01 14:48:49+00', '2021-05-06 16:57:36.762586+00', '2021-05-06 16:57:36.762586+00');
INSERT INTO bdc.timeline VALUES (5, '2020-11-10 13:49:43+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (113, '2020-11-22 14:23:08+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (7, '2020-11-22 14:23:08+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (1, '2021-01-10 13:24:19+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (1, '2021-01-01 13:49:21+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (1, '2021-01-01 13:48:17+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (9, '2020-08-16 22:00:33+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (9, '2020-08-15 13:54:20+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (114, '2020-12-20 14:58:15+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (11, '2020-12-20 14:58:15+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (7, '2020-12-22 13:56:33+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (8, '2020-12-22 13:56:33+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (110, '2020-12-22 13:54:50+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (112, '2020-12-01 13:50:58+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (3, '2020-12-01 13:50:58+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (3, '2020-12-22 13:56:09+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (7, '2020-12-07 14:03:45+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (8, '2020-12-07 14:03:45+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (7, '2019-12-27 14:01:24+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (3, '2019-12-27 14:05:18+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (1, '2020-04-05 11:01:58+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (1, '2020-04-22 16:22:09+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (9, '2020-04-01 13:19:46+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (1, '2020-06-03 15:17:50+00', '2021-05-06 16:57:45.003985+00', '2021-05-06 16:57:45.003985+00');
INSERT INTO bdc.timeline VALUES (16, '1973-05-21 12:38:44+00', '2021-05-06 16:57:46.303415+00', '2021-05-06 16:57:46.303415+00');
INSERT INTO bdc.timeline VALUES (20, '1999-07-31 14:46:54+00', '2021-05-06 16:57:47.829887+00', '2021-05-06 16:57:47.829887+00');
INSERT INTO bdc.timeline VALUES (17, '1982-02-01 14:12:48+00', '2021-05-06 17:14:33.084421+00', '2021-05-06 17:14:33.084421+00');
INSERT INTO bdc.timeline VALUES (18, '1978-04-05 12:17:12+00', '2021-05-06 17:14:34.172475+00', '2021-05-06 17:14:34.172475+00');
INSERT INTO bdc.timeline VALUES (19, '2011-11-01 14:09:55+00', '2021-05-06 17:14:35.386766+00', '2021-05-06 17:14:35.386766+00');


--
-- TOC entry 5596 (class 0 OID 2834035)
-- Dependencies: 238
-- Data for Name: alembic_version; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.alembic_version VALUES ('be5ae740887a');


--
-- TOC entry 5300 (class 0 OID 2832614)
-- Dependencies: 199
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- TOC entry 5624 (class 0 OID 0)
-- Dependencies: 214
-- Name: applications_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.applications_id_seq', 1, false);


--
-- TOC entry 5625 (class 0 OID 0)
-- Dependencies: 217
-- Name: bands_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.bands_id_seq', 1, false);


--
-- TOC entry 5626 (class 0 OID 0)
-- Dependencies: 220
-- Name: collections_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.collections_id_seq', 1, false);


--
-- TOC entry 5627 (class 0 OID 0)
-- Dependencies: 223
-- Name: composite_functions_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.composite_functions_id_seq', 1, false);


--
-- TOC entry 5628 (class 0 OID 0)
-- Dependencies: 225
-- Name: grid_ref_sys_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.grid_ref_sys_id_seq', 1, false);


--
-- TOC entry 5629 (class 0 OID 0)
-- Dependencies: 227
-- Name: items_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.items_id_seq', 1, true);


--
-- TOC entry 5630 (class 0 OID 0)
-- Dependencies: 229
-- Name: mime_type_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.mime_type_id_seq', 1, false);


--
-- TOC entry 5631 (class 0 OID 0)
-- Dependencies: 231
-- Name: providers_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.providers_id_seq', 1, false);


--
-- TOC entry 5632 (class 0 OID 0)
-- Dependencies: 234
-- Name: resolution_unit_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.resolution_unit_id_seq', 1, false);


--
-- TOC entry 5633 (class 0 OID 0)
-- Dependencies: 236
-- Name: tiles_id_seq; Type: SEQUENCE SET; Schema: bdc; Owner: postgres
--

SELECT pg_catalog.setval('bdc.tiles_id_seq', 1708, true);


--
-- TOC entry 5348 (class 2606 OID 2834049)
-- Name: applications applications_name_key; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.applications
    ADD CONSTRAINT applications_name_key UNIQUE (name, version);


--
-- TOC entry 5350 (class 2606 OID 2834051)
-- Name: applications applications_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.applications
    ADD CONSTRAINT applications_pkey PRIMARY KEY (id);


--
-- TOC entry 5352 (class 2606 OID 2834053)
-- Name: band_src band_src_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.band_src
    ADD CONSTRAINT band_src_pkey PRIMARY KEY (band_id, band_src_id);


--
-- TOC entry 5354 (class 2606 OID 2834055)
-- Name: bands bands_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.bands
    ADD CONSTRAINT bands_pkey PRIMARY KEY (id);


--
-- TOC entry 5360 (class 2606 OID 2834057)
-- Name: collection_src collection_src_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collection_src
    ADD CONSTRAINT collection_src_pkey PRIMARY KEY (collection_id, collection_src_id);


--
-- TOC entry 5362 (class 2606 OID 2834059)
-- Name: collections collections_name_key; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections
    ADD CONSTRAINT collections_name_key UNIQUE (name, version);


--
-- TOC entry 5364 (class 2606 OID 2834061)
-- Name: collections collections_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections
    ADD CONSTRAINT collections_pkey PRIMARY KEY (id);


--
-- TOC entry 5369 (class 2606 OID 2834063)
-- Name: collections_providers collections_providers_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections_providers
    ADD CONSTRAINT collections_providers_pkey PRIMARY KEY (provider_id, collection_id);


--
-- TOC entry 5371 (class 2606 OID 2834065)
-- Name: composite_functions composite_functions_alias_key; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.composite_functions
    ADD CONSTRAINT composite_functions_alias_key UNIQUE (alias);


--
-- TOC entry 5373 (class 2606 OID 2834067)
-- Name: composite_functions composite_functions_name_key; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.composite_functions
    ADD CONSTRAINT composite_functions_name_key UNIQUE (name);


--
-- TOC entry 5375 (class 2606 OID 2834069)
-- Name: composite_functions composite_functions_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.composite_functions
    ADD CONSTRAINT composite_functions_pkey PRIMARY KEY (id);


--
-- TOC entry 5377 (class 2606 OID 2834071)
-- Name: grid_ref_sys grid_ref_sys_name_key; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.grid_ref_sys
    ADD CONSTRAINT grid_ref_sys_name_key UNIQUE (name);


--
-- TOC entry 5379 (class 2606 OID 2834073)
-- Name: grid_ref_sys grid_ref_sys_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.grid_ref_sys
    ADD CONSTRAINT grid_ref_sys_pkey PRIMARY KEY (id);


--
-- TOC entry 5390 (class 2606 OID 2834075)
-- Name: items items_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.items
    ADD CONSTRAINT items_pkey PRIMARY KEY (id);


--
-- TOC entry 5392 (class 2606 OID 2834077)
-- Name: mime_type mime_type_name_key; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.mime_type
    ADD CONSTRAINT mime_type_name_key UNIQUE (name);


--
-- TOC entry 5394 (class 2606 OID 2834079)
-- Name: mime_type mime_type_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.mime_type
    ADD CONSTRAINT mime_type_pkey PRIMARY KEY (id);


--
-- TOC entry 5415 (class 2606 OID 2836587)
-- Name: mux_grid mux_grid_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.mux_grid
    ADD CONSTRAINT mux_grid_pkey PRIMARY KEY (id);


--
-- TOC entry 5397 (class 2606 OID 2834081)
-- Name: providers providers_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.providers
    ADD CONSTRAINT providers_pkey PRIMARY KEY (id);


--
-- TOC entry 5399 (class 2606 OID 2834083)
-- Name: quicklook quicklook_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.quicklook
    ADD CONSTRAINT quicklook_pkey PRIMARY KEY (collection_id);


--
-- TOC entry 5401 (class 2606 OID 2834085)
-- Name: resolution_unit resolution_unit_name_key; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.resolution_unit
    ADD CONSTRAINT resolution_unit_name_key UNIQUE (name);


--
-- TOC entry 5403 (class 2606 OID 2834087)
-- Name: resolution_unit resolution_unit_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.resolution_unit
    ADD CONSTRAINT resolution_unit_pkey PRIMARY KEY (id);


--
-- TOC entry 5408 (class 2606 OID 2834089)
-- Name: tiles tiles_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.tiles
    ADD CONSTRAINT tiles_pkey PRIMARY KEY (id);


--
-- TOC entry 5411 (class 2606 OID 2834091)
-- Name: timeline timeline_pkey; Type: CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.timeline
    ADD CONSTRAINT timeline_pkey PRIMARY KEY (collection_id, time_inst);


--
-- TOC entry 5413 (class 2606 OID 2834093)
-- Name: alembic_version alembic_version_pkc; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alembic_version
    ADD CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num);


--
-- TOC entry 5355 (class 1259 OID 2834094)
-- Name: idx_bdc_bands_collection_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_bands_collection_id ON bdc.bands USING btree (collection_id);


--
-- TOC entry 5356 (class 1259 OID 2834095)
-- Name: idx_bdc_bands_common_name; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_bands_common_name ON bdc.bands USING btree (common_name);


--
-- TOC entry 5357 (class 1259 OID 2834096)
-- Name: idx_bdc_bands_mime_type_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_bands_mime_type_id ON bdc.bands USING btree (mime_type_id);


--
-- TOC entry 5358 (class 1259 OID 2834097)
-- Name: idx_bdc_bands_name; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_bands_name ON bdc.bands USING btree (name);


--
-- TOC entry 5365 (class 1259 OID 2834098)
-- Name: idx_bdc_collections_extent; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_collections_extent ON bdc.collections USING gist (extent);


--
-- TOC entry 5366 (class 1259 OID 2834099)
-- Name: idx_bdc_collections_grid_ref_sys_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_collections_grid_ref_sys_id ON bdc.collections USING btree (grid_ref_sys_id);


--
-- TOC entry 5367 (class 1259 OID 2834100)
-- Name: idx_bdc_collections_name; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_collections_name ON bdc.collections USING btree (name);


--
-- TOC entry 5380 (class 1259 OID 2834101)
-- Name: idx_bdc_items_cloud_cover; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_cloud_cover ON bdc.items USING btree (cloud_cover);


--
-- TOC entry 5381 (class 1259 OID 2834102)
-- Name: idx_bdc_items_collection_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_collection_id ON bdc.items USING btree (collection_id);


--
-- TOC entry 5382 (class 1259 OID 2834103)
-- Name: idx_bdc_items_geom; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_geom ON bdc.items USING gist (geom);


--
-- TOC entry 5383 (class 1259 OID 2834104)
-- Name: idx_bdc_items_min_convex_hull; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_min_convex_hull ON bdc.items USING gist (min_convex_hull);


--
-- TOC entry 5384 (class 1259 OID 2834105)
-- Name: idx_bdc_items_name; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_name ON bdc.items USING btree (name);


--
-- TOC entry 5385 (class 1259 OID 2834106)
-- Name: idx_bdc_items_provider_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_provider_id ON bdc.items USING btree (provider_id);


--
-- TOC entry 5386 (class 1259 OID 2834107)
-- Name: idx_bdc_items_start_date; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_start_date ON bdc.items USING btree (start_date DESC);


--
-- TOC entry 5387 (class 1259 OID 2834108)
-- Name: idx_bdc_items_tile_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_items_tile_id ON bdc.items USING btree (tile_id);


--
-- TOC entry 5395 (class 1259 OID 2834109)
-- Name: idx_bdc_providers_name; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_providers_name ON bdc.providers USING btree (name);


--
-- TOC entry 5404 (class 1259 OID 2834110)
-- Name: idx_bdc_tiles_grid_ref_sys_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_tiles_grid_ref_sys_id ON bdc.tiles USING btree (grid_ref_sys_id);


--
-- TOC entry 5405 (class 1259 OID 2834111)
-- Name: idx_bdc_tiles_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_tiles_id ON bdc.tiles USING btree (id);


--
-- TOC entry 5406 (class 1259 OID 2834112)
-- Name: idx_bdc_tiles_name; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_tiles_name ON bdc.tiles USING btree (name);


--
-- TOC entry 5409 (class 1259 OID 2834113)
-- Name: idx_bdc_timeline_collection_id; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_bdc_timeline_collection_id ON bdc.timeline USING btree (collection_id, time_inst DESC);


--
-- TOC entry 5388 (class 1259 OID 2834114)
-- Name: idx_items_start_date_end_date; Type: INDEX; Schema: bdc; Owner: postgres
--

CREATE INDEX idx_items_start_date_end_date ON bdc.items USING btree (start_date, end_date);


--
-- TOC entry 5440 (class 2620 OID 2834115)
-- Name: bands check_bands_metadata_index_trigger; Type: TRIGGER; Schema: bdc; Owner: postgres
--

CREATE TRIGGER check_bands_metadata_index_trigger AFTER INSERT OR UPDATE ON bdc.bands FOR EACH ROW EXECUTE PROCEDURE public.check_bands_metadata_index();


--
-- TOC entry 5441 (class 2620 OID 2834116)
-- Name: items update_collection_time_trigger; Type: TRIGGER; Schema: bdc; Owner: postgres
--

CREATE TRIGGER update_collection_time_trigger AFTER INSERT OR UPDATE ON bdc.items FOR EACH ROW EXECUTE PROCEDURE public.update_collection_time();


--
-- TOC entry 5442 (class 2620 OID 2834117)
-- Name: items update_update_timeline_trigger; Type: TRIGGER; Schema: bdc; Owner: postgres
--

CREATE TRIGGER update_update_timeline_trigger AFTER INSERT OR UPDATE ON bdc.items FOR EACH ROW EXECUTE PROCEDURE public.update_timeline();


--
-- TOC entry 5416 (class 2606 OID 2834118)
-- Name: band_src band_src_band_id_bands_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.band_src
    ADD CONSTRAINT band_src_band_id_bands_fkey FOREIGN KEY (band_id) REFERENCES bdc.bands(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5417 (class 2606 OID 2834123)
-- Name: band_src band_src_band_src_id_bands_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.band_src
    ADD CONSTRAINT band_src_band_src_id_bands_fkey FOREIGN KEY (band_src_id) REFERENCES bdc.bands(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5418 (class 2606 OID 2834128)
-- Name: bands bands_collection_id_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.bands
    ADD CONSTRAINT bands_collection_id_collections_fkey FOREIGN KEY (collection_id) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5419 (class 2606 OID 2834133)
-- Name: bands bands_mime_type_id_mime_type_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.bands
    ADD CONSTRAINT bands_mime_type_id_mime_type_fkey FOREIGN KEY (mime_type_id) REFERENCES bdc.mime_type(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5420 (class 2606 OID 2834138)
-- Name: bands bands_resolution_unit_id_resolution_unit_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.bands
    ADD CONSTRAINT bands_resolution_unit_id_resolution_unit_fkey FOREIGN KEY (resolution_unit_id) REFERENCES bdc.resolution_unit(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5421 (class 2606 OID 2834143)
-- Name: collection_src collection_src_collection_id_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collection_src
    ADD CONSTRAINT collection_src_collection_id_collections_fkey FOREIGN KEY (collection_id) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5422 (class 2606 OID 2834148)
-- Name: collection_src collection_src_collection_src_id_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collection_src
    ADD CONSTRAINT collection_src_collection_src_id_collections_fkey FOREIGN KEY (collection_src_id) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5423 (class 2606 OID 2834153)
-- Name: collections collections_composite_function_id_composite_functions_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections
    ADD CONSTRAINT collections_composite_function_id_composite_functions_fkey FOREIGN KEY (composite_function_id) REFERENCES bdc.composite_functions(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5424 (class 2606 OID 2834158)
-- Name: collections collections_grid_ref_sys_id_grid_ref_sys_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections
    ADD CONSTRAINT collections_grid_ref_sys_id_grid_ref_sys_fkey FOREIGN KEY (grid_ref_sys_id) REFERENCES bdc.grid_ref_sys(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5427 (class 2606 OID 2834163)
-- Name: collections_providers collections_providers_collection_id_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections_providers
    ADD CONSTRAINT collections_providers_collection_id_collections_fkey FOREIGN KEY (collection_id) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5428 (class 2606 OID 2834168)
-- Name: collections_providers collections_providers_provider_id_providers_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections_providers
    ADD CONSTRAINT collections_providers_provider_id_providers_fkey FOREIGN KEY (provider_id) REFERENCES bdc.providers(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5425 (class 2606 OID 2834173)
-- Name: collections collections_version_predecessor_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections
    ADD CONSTRAINT collections_version_predecessor_collections_fkey FOREIGN KEY (version_predecessor) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5426 (class 2606 OID 2834178)
-- Name: collections collections_version_successor_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.collections
    ADD CONSTRAINT collections_version_successor_collections_fkey FOREIGN KEY (version_successor) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5429 (class 2606 OID 2834183)
-- Name: items items_application_id_applications_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.items
    ADD CONSTRAINT items_application_id_applications_fkey FOREIGN KEY (application_id) REFERENCES bdc.applications(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5430 (class 2606 OID 2834188)
-- Name: items items_collection_id_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.items
    ADD CONSTRAINT items_collection_id_collections_fkey FOREIGN KEY (collection_id) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5431 (class 2606 OID 2834193)
-- Name: items items_provider_id_providers_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.items
    ADD CONSTRAINT items_provider_id_providers_fkey FOREIGN KEY (provider_id) REFERENCES bdc.providers(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5432 (class 2606 OID 2834198)
-- Name: items items_srid_spatial_ref_sys_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.items
    ADD CONSTRAINT items_srid_spatial_ref_sys_fkey FOREIGN KEY (srid) REFERENCES public.spatial_ref_sys(srid) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5433 (class 2606 OID 2834203)
-- Name: items items_tile_id_tiles_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.items
    ADD CONSTRAINT items_tile_id_tiles_fkey FOREIGN KEY (tile_id) REFERENCES bdc.tiles(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5434 (class 2606 OID 2834208)
-- Name: quicklook quicklook_blue_bands_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.quicklook
    ADD CONSTRAINT quicklook_blue_bands_fkey FOREIGN KEY (blue) REFERENCES bdc.bands(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5435 (class 2606 OID 2834213)
-- Name: quicklook quicklook_collection_id_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.quicklook
    ADD CONSTRAINT quicklook_collection_id_collections_fkey FOREIGN KEY (collection_id) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5436 (class 2606 OID 2834218)
-- Name: quicklook quicklook_green_bands_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.quicklook
    ADD CONSTRAINT quicklook_green_bands_fkey FOREIGN KEY (green) REFERENCES bdc.bands(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5437 (class 2606 OID 2834223)
-- Name: quicklook quicklook_red_bands_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.quicklook
    ADD CONSTRAINT quicklook_red_bands_fkey FOREIGN KEY (red) REFERENCES bdc.bands(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5438 (class 2606 OID 2834228)
-- Name: tiles tiles_grid_ref_sys_id_grid_ref_sys_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.tiles
    ADD CONSTRAINT tiles_grid_ref_sys_id_grid_ref_sys_fkey FOREIGN KEY (grid_ref_sys_id) REFERENCES bdc.grid_ref_sys(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5439 (class 2606 OID 2834233)
-- Name: timeline timeline_collection_id_collections_fkey; Type: FK CONSTRAINT; Schema: bdc; Owner: postgres
--

ALTER TABLE ONLY bdc.timeline
    ADD CONSTRAINT timeline_collection_id_collections_fkey FOREIGN KEY (collection_id) REFERENCES bdc.collections(id) ON UPDATE CASCADE ON DELETE CASCADE;


-- Completed on 2021-05-06 17:18:02 UTC

--
-- PostgreSQL database dump complete
--

