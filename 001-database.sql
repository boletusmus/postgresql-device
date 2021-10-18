CREATE EXTENSION pgcrypto; -- uuid type dependency

-- SELECT current_database(); -- alfa
-- select uuid_generate_v4()
-- SELECT gen_random_uuid();
-- select uuid_generate_v1mc();

create sequence device_type_id;

-- drop table public.device_type;

create table public.device_type
(
id smallint primary key default nextval('device_type_id'),
type text not null unique
);

-- SELECT currval('device_type_id');

select * from public.device_type;

insert into public.device_type (type) values ('single_a') ON CONFLICT DO NOTHING;
insert into public.device_type (type) values ('single_b') ON CONFLICT DO NOTHING;
insert into public.device_type (type) values ('multi_a') ON CONFLICT DO NOTHING;
insert into public.device_type (type) values ('multi_b') ON CONFLICT DO NOTHING;
insert into public.device_type (type) values ('single_a_1') ON CONFLICT DO NOTHING;
insert into public.device_type (type) values ('single_a_2') ON CONFLICT DO NOTHING;
insert into public.device_type (type) values ('single_b_1') ON CONFLICT DO NOTHING;
insert into public.device_type (type) values ('single_b_2') ON CONFLICT DO NOTHING;
insert into public.device_type (type) values ('single_a_3') ON CONFLICT DO NOTHING;

-- drop table public.device_type_subtypes;


create table public.device_type_subtypes
(
id smallint primary key default nextval('device_type_id'),
type text not null,
subtype text not null,
constraint uq_device_type_subtypes unique (type,subtype)
);

insert into public.device_type_subtypes (type,subtype) values ('multi_a','single_a_1') ON CONFLICT DO NOTHING;
insert into public.device_type_subtypes (type,subtype) values ('multi_a','single_a_2') ON CONFLICT DO NOTHING;
insert into public.device_type_subtypes (type,subtype) values ('multi_b','single_b_1') ON CONFLICT DO NOTHING;
insert into public.device_type_subtypes (type,subtype) values ('multi_b','single_b_2') ON CONFLICT DO NOTHING;

select * from public.device_type;
select * from public.device_type_subtypes;

create table public.device
(
id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
name text not null,
type text not null,
constraint uq_device unique (name,type)
);

-- alan:    single_b_1, single_b_2, single_b_3
insert into public.device (name,type) values ('alan','single_b_1') ON CONFLICT DO NOTHING;
insert into public.device (name,type) values ('alan','single_b_2') ON CONFLICT DO NOTHING;
insert into public.device (name,type) values ('alan','single_b_3') ON CONFLICT DO NOTHING;
-- beata:   single_b_1, single_b_2
insert into public.device (name,type) values ('beata','multi_b') ON CONFLICT DO NOTHING;
-- celina:  single_b_1(*), single_b_2
insert into public.device (name,type) values ('celina','single_b_1') ON CONFLICT DO NOTHING;
insert into public.device (name,type) values ('celina','multi_b') ON CONFLICT DO NOTHING;

-- possible misconfigurations:
select *
from public.device d1 inner join public.device d2 on d1.name = d2.name
inner join public.device_type_subtypes s on ((s.type=d1.type and s.subtype=d2.type) or (s.subtype=d1.type and s.type=d2.type))
where d1.id < d2.id

with misconfigured_names as (
    select
        d.name
    from
        public.device d
    group by d.name
    having (
        exists(
            select *
            from
                public.device d1 
                inner join public.device d2 on d1.name = d2.name
                inner join public.device_type_subtypes s on ((s.type=d1.type and s.subtype=d2.type) or (s.subtype=d1.type and s.type=d2.type))
            where
                d1.id < d2.id 
                and d1.name=d.name
        )
    )
)
select d.* from public.device d inner join misconfigured_names x on d.name=x.name;


select * from public.device;

create table public.readings
(
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id uuid not null,
    value decimal (12,3) not null,
    read timestamp without time zone not null
);
create table public.readings_rejected
(
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text not null,
    type text not null,
    value decimal (12,3) not null,
    read timestamp without time zone not null
);

select * from readings;
select * from readings_rejected;


-- SELECT version();


create or replace function missconfigured_devices (
    ) returns setof public.device
as $$

with misconfigured_names as (
    select
        d.name
    from
        public.device d
    group by d.name
    having (
        exists(
            select *
            from
                public.device d1 
                inner join public.device d2 on d1.name = d2.name
                inner join public.device_type_subtypes s on ((s.type=d1.type and s.subtype=d2.type) or (s.subtype=d1.type and s.type=d2.type))
            where
                d1.id < d2.id 
                and d1.name=d.name
        )
    )
)
select d.* from public.device d inner join misconfigured_names x on d.name=x.name;
$$
language sql;

create or replace function insert_measure (
    aname text,
    atype text,
    aval decimal(12,3),
    aread timestamp without time zone
    ) returns void
as $$

insert into public.readings (device_id, value, read)
select
    w.id,
    w.val,
    w.read
from (
    select
        d.id,
        aval as val,
        aread as read
    from
        public.device d
    where
        (d.name=aname) and (d.type=atype)
    union all
    select
        d.id,
        aval as val,
        aread as read
    from
        public.device d
        inner join public.device_type_subtypes s on d.type=s.type
    where
        (d.name=aname)
        and (s.subtype=atype)
        and not exists (select * from public.device dd where (dd.name=aname) and (dd.type=atype))
) w
where exists (select * from public.device dd where dd.id=w.id)
ON CONFLICT DO NOTHING;

insert into public.readings_rejected (name,type,value,read)
select
    aname,
    atype,
    aval,
    aread
where not exists (
    select *
    from
        public.device d 
        left join public.device_type_subtypes s on d.type=s.type
    where
        ((d.name=aname) and (d.type=atype)) or ((d.name=aname) and (s.subtype=atype))
    )
ON CONFLICT DO NOTHING;
$$
language sql
returns null on null input;


select missconfigured_devices();

select insert_measure('alan', 'single_b_1', 1.3, LOCALTIMESTAMP);
select insert_measure('alan', 'single_b_2', 2.3, LOCALTIMESTAMP);
select insert_measure('alan', 'single_b_3', 3.3, LOCALTIMESTAMP);
select insert_measure('alan', 'single_a_1', 4.3, LOCALTIMESTAMP);          --
select insert_measure('beata', 'single_a_1', 5.3, LOCALTIMESTAMP);         --
select insert_measure('beata', 'multi_b', 6.3, LOCALTIMESTAMP);
    select insert_measure('beata', 'single_b_1', 7.3, LOCALTIMESTAMP);
    select insert_measure('beata', 'single_b_2', 8.3, LOCALTIMESTAMP);
    select insert_measure('beata', 'single_b_3', 9.3, LOCALTIMESTAMP);     --
select insert_measure('celina', 'multi_b', 10.3, LOCALTIMESTAMP);
    select insert_measure('celina', 'single_b_1', 11.3, LOCALTIMESTAMP);
    select insert_measure('celina', 'single_a_1', 12.3, LOCALTIMESTAMP);    --

select * from public.device where name='alan'
select * from public.device where type='single_a_1'
select * from public.device where id='0c9cdbfe-0ca5-4864-8712-68a5269e60fb'::uuid

truncate public.readings;
truncate public.readings_rejected;

select * from public.readings;
select * from public.readings_rejected;

select r.id, d.* from public.readings r inner join public.device d on d.id=r.device_id;


drop table public.software;

select * from public.software;

create sequence sotware_id;

create table public.software (
id int not null default nextval('sotware_id') primary key
,name text not null unique
);

select * from public.software s ;

-- drop function insert_software(text);
create or replace function insert_software(aname text) returns boolean
as $$
with insert_rows as (
	insert into public.software (name)
	values ($1)
	on conflict do nothing
	returning 1
)
select count(*)>0 from insert_rows;
$$
language sql;

create or replace function update_software(id int, name text) returns boolean
as $$
with update_rows as (
	update public.software
	set name=$2
	where id=$1
	returning 1
)
select count(*)>0 from update_rows;
$$
language sql;


select insert_software('notepad+++');
select update_software(14,'Notepad++');
