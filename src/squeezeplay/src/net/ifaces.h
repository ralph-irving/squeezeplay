/* Returns a NULL-terminated array of directed broadcast address strings
 * (e.g. "192.168.1.255"). Caller must free with ifaces_free().
 * Returns NULL on error. */
char **ifaces_get(void);

void ifaces_free(char **list);
