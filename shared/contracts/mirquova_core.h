#ifndef MIRQUOVA_CORE_H
#define MIRQUOVA_CORE_H
#include <stdint.h>
// ABI 2 plus additive pairing identity symbols; presence is still untrusted.
uint32_t mq_abi_version(void);
int32_t mq_discovery_start(void);
void mq_discovery_stop(void);
// Owned UTF-8 JSON. Free exactly once through mq_string_free.
char *mq_discovery_snapshot(void);
void mq_string_free(char *value);
// UTF-8 alias, 1-64 bytes; caller keeps ownership. 1 started, 0 rejected, -1 failure.
int32_t mq_presence_start(const uint8_t *alias, uint32_t alias_len);
void mq_presence_stop(void);
// Secret-bearing identity material; store the key only in OS-backed storage.
typedef struct mq_pairing_identity {
    uint8_t *certificate_der;
    uint32_t certificate_len;
    uint8_t *private_key_pkcs8_der;
    uint32_t private_key_len;
} mq_pairing_identity;
mq_pairing_identity *mq_pairing_identity_create(void);
// Wipes and frees the returned buffers and descriptor.
void mq_pairing_identity_free(mq_pairing_identity *identity);
// 1 valid matching CA/key, 0 invalid input/material, -1 internal failure.
int32_t mq_pairing_identity_validate(const uint8_t *certificate_der,
                                     uint32_t certificate_len,
                                     const uint8_t *private_key_pkcs8_der,
                                     uint32_t private_key_len);
// Starts an explicitly requested 120-second host session and returns its
// secret-bearing v2 invitation JSON. Bind only to a selected private IPv4.
char *mq_pairing_host_start(const uint8_t *local_ipv4, uint32_t address_len,
                            uint16_t port, const uint8_t *host_alias,
                            uint32_t alias_len, const uint8_t *certificate_der,
                            uint32_t certificate_len,
                            const uint8_t *private_key_pkcs8_der,
                            uint32_t private_key_len);
// Starts a join attempt only after UI fingerprint comparison/confirmation.
int32_t mq_pairing_join(const uint8_t *invitation_json, uint32_t payload_len,
                        const uint8_t *confirmed_fingerprint_sha256,
                        const uint8_t *identity_ca_certificate_der,
                        uint32_t certificate_len,
                        const uint8_t *private_key_pkcs8_der,
                        uint32_t private_key_len, const uint8_t *alias,
                        uint32_t alias_len);
int32_t mq_pairing_approve(void);
int32_t mq_pairing_reject(void);
// JSON contains only state and public candidate CA bytes. Free with mq_string_free.
char *mq_pairing_snapshot(void);
void mq_pairing_stop(void);
#endif
