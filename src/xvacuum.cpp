#include "xvacuum.h"
#include <string>
#include <url.h>
#include <util.h>
#include "gpcleaner.h"
#include "gucs.h"
#include "pg.h"

/*
 * yezzey_delete_chunk_internal:
 * Given external chunk path, remove it from external storage
 * TBD: check, that chukn status is obsolete and other sanity checks
 * to avoid deleting chunk, which can we needed to read relation data
 */
int yezzey_delete_chunk_internal(
    const char *external_chunk_path) {
  try {
    auto ioadv = std::make_shared<IOadv>(
              std::string(gpg_engine_path), std::string(gpg_key_id),
              std::string(storage_config), "", "",
              std::string(storage_host /*host*/),
              std::string(storage_bucket /*bucket*/),
              std::string(storage_prefix /*prefix*/), "" /* coords */,
              InvalidOid /* reloid */, std::string(walg_bin_path),
              std::string(walg_config_path), use_gpg_crypto);

    auto x_path = std::string(external_chunk_path);
    auto cleaner = cleaner_init(
        (getYezzeyExtrenalStorageBucket(ioadv->host.c_str(),
                                        ioadv->bucket.c_str()) +
         storage_url_add_options(x_path, ioadv->config_path.c_str()))
            .c_str());
    int rc = cleaner->clean();
  } catch (...) {
    elog(ERROR, "failed to prepare x-storage reader for chunk");
  }
}
