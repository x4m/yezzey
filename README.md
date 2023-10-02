## Yezzey

Yezzey is a GreenplumDB extension, which makes data offloading in GP easy.

Yezzey defines API for creating data offloading policies and attach these policies to tables.

Data offloading means physical move of relation data to external cloud storage, namely S3.

Difficulties:

- no generic wal availabale in gp6 (pg 9.4)
- no custom access method in pg9.4
- no custom wal redo routines

# Design goals:

Greenplum 6 compatibility.

Avoid binary incompatibilities, such as custom WAL records, which will not be replayabe in upstream GP.

Try to avoid custom relation forks, use of which need to be somehow WAL-logged or handled separately. This would mean additional backup/restore complexity and corner cases to handle.

# API

Yezzey defines custom smgr for AO/AOCS related storage operations.

### Read-write operations

Table reading logic is the following:

Case: AO/AOCS file segments being read throught yezzey SMGR. Filename to be accessed is in form

base/\<dboid\>/\<tableoid\>.\<segnum\>


Read/write logic in GP with AO/AOCS tables works in following way:

* In case of read operation,
* Open AO/AOCS segment file.
* Set read/write offset to either 0 or $logicalEof
* Read/Write X bytes
* Close file


So, our read logic will be following:

1) Check if relation belongs to Yezzey virtual tablespace (YEZZEYTABLESPACE_OID == 5555). If yes, this means table (and this segment file) was not (yet) offloaded to external storage. So, process normally.
2) If not, try to search for file with prefix segment<gpsegment>/base/<dboid>/<tableoid>.<segnum>.<current_read_offset>* with highest epoch number is external storage (S3). Is there is,
   read them in lexicographically ascending order. Sum of sizes of external files should be >= than logical EOF (which can be found in pg_aoseg.pg_aoseg_<tableoid> table). 
   TDB: fix this to support proper VACUUM processing on offloaded relation, using yezzey_virtual_index relation (which tracks all extrenal chunks)
   
3) Read this file, while not exhausted
4) If any failure, there is probably a corruption by to some unknown bugs in implementation.

### Offloading API and implementation

Algo of AO/AOCS table offloading:

1) Lock AO/AOCS relation in pg_class in exclusive mode. This prevents other concurrent sessions to read or write anything from this table.
2) Write all table segments files to s3, one by one. Write them with name segment<gpsegment>/base/<dboid>/<tableoid>.<segnum>.0 (last number means that zero is this file logical eof start)
3) Change relation tablespace to Yezzey virual tablespace (with pre-defined oid = 8555)

Write to already offloaded AO/AOCS segment logic is following:

1) For each AO/AOCS segment we firstly resolve highest epoch in which these changes are made. This is the last number from the lexicographically largest segment<gpsegment>/base/\<dboid\>/\<tableoid\>.\<segnum\>.0.* file. Let in be Y
2) Write new file with name  segment<gpsegment>/base/\<dboid\>/\<tableoid\>.\<segnum\>.\<current_write_offset=logical_end_of_file\>.Y
3) success

```


      /------\                   Cloud (external storage) e.g. S3
     |\______/|                /-------\
     |  GP    |               (         )
     | segment|     ----->     \vvvvvvv/
     |\______/|
     |        |
     |        |
      \______/
```



## end


# Vacuum

Need to change relfilenode while vacuuming yezzey relations, since yezzey does not support truncate operation propetly.


Install:
see dev-scrupt folder
