#ifndef MIRQUOVA_CORE_H
#define MIRQUOVA_CORE_H
#include <stdint.h>
// ABI 2; scan and explicit two-minute presence. No authenticated identity.
uint32_t mq_abi_version(void);
int32_t mq_discovery_start(void);
void mq_discovery_stop(void);
// Owned UTF-8 JSON. Free exactly once through mq_string_free.
char *mq_discovery_snapshot(void);
void mq_string_free(char *value);
// UTF-8 alias, 1-64 bytes; caller keeps ownership. 1 started, 0 rejected, -1 failure.
int32_t mq_presence_start(const uint8_t *alias, uint32_t alias_len);
void mq_presence_stop(void);
#endif
