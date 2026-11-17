/*-------------------------------------------------------------------------
 *
 * pglogical_relcache.h
 *		pglogical relation cache
 *
 * Copyright (c) 2015, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *		pglogical_relcache.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PGLOGICAL_RELCACHE_H
#define PGLOGICAL_RELCACHE_H

#include "storage/lock.h"

typedef struct PGLogicalRemoteRel
{
	uint32		relid;
	char	   *nspname;
	char	   *relname;
	int			natts;
	char	  **attnames;

	/* Only returned by info function, not protocol. */
	bool		hasRowFilter;
} PGLogicalRemoteRel;

typedef struct PGLogicalRelation
{
	/* Info coming from the remote side. */
	uint32		remoteid;
	char	   *nspname;
	char	   *relname;
	/* Subscriber-side names; default to the remote names. */
	char	   *local_nspname;
	char	   *local_relname;
	int			natts;
	char	  **attnames;

	/* Mapping to local relation, filled as needed. */
	Oid			reloid;
	Relation	rel;
	int		   *attmap;

	/* Additional cache, only valid as long as relation mapping is. */
	bool		hasTriggers;
} PGLogicalRelation;

#define PGLOGICAL_LOCAL_NSPNAME(rel) \
	((rel)->local_nspname != NULL ? (rel)->local_nspname : (rel)->nspname)
#define PGLOGICAL_LOCAL_RELNAME(rel) \
	((rel)->local_relname != NULL ? (rel)->local_relname : (rel)->relname)

extern void pglogical_relation_cache_update(uint32 remoteid,
												 char *schemaname, char *relname,
												 char *local_schemaname, char *local_relname,
											 int natts, char **attnames);
extern void pglogical_relation_cache_updater(PGLogicalRemoteRel *remoterel);
extern void pglogical_get_local_relation_names(Oid subid,
											   const char *remote_nspname,
											   char **local_nspname,
											   char **local_relname);

extern PGLogicalRelation *pglogical_relation_open(uint32 remoteid,
												   LOCKMODE lockmode);
extern void pglogical_relation_close(PGLogicalRelation * rel,
									  LOCKMODE lockmode);
extern void pglogical_relation_invalidate_cb(Datum arg, Oid reloid);

struct PGLogicalTupleData;

#endif /* PGLOGICAL_RELCACHE_H */
