#include "lua.h"
#include "lauxlib.h"
#include "ifaces.h"

static int jiveL_ifaces_broadcasts(lua_State *L)
{
    char **list = ifaces_get();

    lua_newtable(L);
    if (list) {
        int i = 1;
        for (char **p = list; *p; p++) {
            lua_pushstring(L, *p);
            lua_rawseti(L, -2, i++);
        }
        ifaces_free(list);
    }
    return 1;
}

static const struct luaL_Reg ifaces_lib[] = {
    { "broadcasts", jiveL_ifaces_broadcasts },
    { NULL, NULL }
};

int luaopen_jive_net_ifaces(lua_State *L) {
    luaL_register(L, "jive.ifaces", ifaces_lib);
    return 0;
}
