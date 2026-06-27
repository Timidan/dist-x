/* Auto-generated C header for distributionx FFI. DO NOT EDIT. */
#ifndef DISTRIBUTIONX_FFI_H
#define DISTRIBUTIONX_FFI_H

#ifdef __cplusplus
extern "C" {
#endif

/* init_airdrop instruction */
char* distributionx_init_airdrop(const char* args_json);

/* fund instruction */
char* distributionx_fund(const char* args_json);

/* claim instruction */
char* distributionx_claim(const char* args_json);

/* claim_private instruction */
char* distributionx_claim_private(const char* args_json);

/* claim_ppe instruction */
char* distributionx_claim_ppe(const char* args_json);

/* close instruction */
char* distributionx_close(const char* args_json);

void distributionx_free_string(char* s);
char* distributionx_version(void);

#ifdef __cplusplus
}
#endif

#endif /* DISTRIBUTIONX_FFI_H */
