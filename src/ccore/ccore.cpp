#include "ccore/ccore.hpp"
#include <spdlog/spdlog.h>

namespace by2
{
    int32_t ccore_add(int32_t a, int32_t b)
    {
        spdlog::info("adding {} + {}, a, b");
        return a + b;
    }
}
