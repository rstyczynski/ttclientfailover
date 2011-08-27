drop table nodeInfo;
create table nodeinfo (
    key varchar(100),
    value varchar(200),

    primary key (key)
);
insert into nodeinfo values ('host','ozone2');