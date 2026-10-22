#include "ifaces.h"
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <string.h>
#include <stdlib.h>

char **ifaces_get(void)
{
    struct ifaddrs *ifaddr, *ifa;
    char **list = NULL;
    int n = 0, cap = 0;

    if (getifaddrs(&ifaddr) != 0)
        return NULL;

    for (ifa = ifaddr; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET)
            continue;
        if (!(ifa->ifa_flags & IFF_UP))
            continue;
        if (ifa->ifa_flags & IFF_LOOPBACK)
            continue;

        struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
        struct sockaddr_in *mask = (struct sockaddr_in *)ifa->ifa_netmask;
        if (!mask)
            continue;

        uint32_t ip   = ntohl(sin->sin_addr.s_addr);
        uint32_t msk  = ntohl(mask->sin_addr.s_addr);
        uint32_t bcast = ip | ~msk;

        struct in_addr ba = { .s_addr = htonl(bcast) };
        char buf[INET_ADDRSTRLEN];
        if (!inet_ntop(AF_INET, &ba, buf, sizeof(buf)))
            continue;

        /* grow list */
        if (n + 1 >= cap) {
            int old_cap = cap;
            cap = cap ? cap * 2 : 8;
            char **new_list = realloc(list, cap * sizeof(*list));
            if (!new_list) {
                ifaces_free(list);
                freeifaddrs(ifaddr);
                return NULL;
            }
            list = new_list;
            memset(list + old_cap, 0, (cap - old_cap) * sizeof(*list));
        }
        list[n++] = strdup(buf);
    }
    freeifaddrs(ifaddr);

    if (list)
        list[n] = NULL;

    return list;
}

void ifaces_free(char **list)
{
    if (!list) return;

    int i = 0;
    while (list[i] != NULL) {
        free(list[i]);
        list[i] = NULL;
        i++;
    }

    free(list);
}
