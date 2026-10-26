#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <unordered_set>
#include <vector>

#include "dbcomid.hpp"
#include "fflerror.hpp"
#include "hexstr.hpp"
#include "itemrecord.hpp"
#include "gui/ImSkillBoard.hpp"
#include "mir2xmapdata.hpp"
#include "strf.hpp"
#include "totype.hpp"
#include "zsdb.hpp"

namespace fs = std::filesystem;

// --no-png：只输出索引/元数据，不写逐帧 PNG。
// Godot 客户端已改为直接读取 ZSDB（client_godot/scripts/resource/），
// 全量导出 37 万个 PNG 既慢又占 2.6G 磁盘，默认构建不再需要。
static bool g_noPNG = false;

static bool consumeFlag(int &argc, char *argv[], const char *flag)
{
    for(int index = 1; index < argc; ++index){
        if(std::strcmp(argv[index], flag) != 0){
            continue;
        }
        for(int move = index; move + 1 < argc; ++move){
            argv[move] = argv[move + 1];
        }
        --argc;
        return true;
    }
    return false;
}

#pragma pack(push, 1)
struct MapHeader
{
    char magic[4] {'M', '2', 'G', 'W'};
    uint32_t version = 1;
    uint32_t mapID = 0;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t tileCount = 0;
    uint32_t objectCount = 0;
};

struct TileRecord
{
    uint16_t x = 0;
    uint16_t y = 0;
    uint32_t textureID = 0;
};

struct ObjectRecord
{
    uint16_t x = 0;
    uint16_t y = 0;
    uint32_t textureID = 0;
    uint8_t depth = 0;
    uint8_t flags = 0;
    uint8_t tickType = 0;
    uint8_t frameCount = 0;
};

struct SpriteHeader
{
    char magic[4] {'M', '2', 'S', 'P'};
    uint32_t version = 1;
    uint32_t spriteCount = 0;
};

struct SpriteRecord
{
    uint32_t key = 0;
    int16_t dx = 0;
    int16_t dy = 0;
};

struct MonsterMetaRecord
{
    uint32_t monsterID = 0;
    uint16_t lookID = 0;
    uint8_t shadow = 0;
    uint8_t reserved = 0;
    uint32_t spawnSeffID = UINT32_MAX;
    uint32_t attackSeffID = UINT32_MAX;
    uint32_t hittedSeffID = UINT32_MAX;
    uint32_t dieSeffID = UINT32_MAX;
    uint16_t spawnLookID = 0;
    uint16_t hiddenLookID = 0;
    uint8_t hiddenStandMotion = 0;
    uint8_t hiddenStandBegin = 0;
    uint8_t hiddenStandCount = 0;
    uint8_t activeTransfMotion = 0;
    uint8_t activeTransfBegin = 0;
    uint8_t activeTransfCount = 0;
    uint8_t hiddenTransfMotion = 0;
    uint8_t hiddenTransfBegin = 0;
    uint8_t hiddenTransfCount = 0;
    uint8_t transfFlags = 0;
    uint32_t deathMagicID = 0;
    uint32_t attackMotionMagicID = 0;
    uint32_t transformEffectMagicID = 0;
    uint32_t spawnEffectMagicID = 0;
    uint8_t bodyStandMotionID = 0;
    uint8_t bodyStandFrameCount = 0;
    uint8_t bodyAttackMotionID = 0;
    uint8_t bodyAttackFrameCount = 0;
    uint32_t bodyAltAttackMagicID = 0;
    uint8_t bodyAltAttackMotionID = 0;
    uint8_t bodyAltAttackFrameCount = 0;
    uint8_t bodyFlags = 0;
    uint8_t spawnDirection = 0;
    uint8_t motionCorrectionFlags = 0;
    uint8_t behaveMode = 0;
};

struct ItemMetaRecord
{
    uint32_t itemID = 0;
    uint16_t shape = 0;
    uint16_t reserved = 0;
    uint32_t pkgGfxID = 0;

    int32_t weight = 0;
    int32_t dc[2] {};
    int32_t mc[2] {};
    int32_t sc[2] {};
    int32_t ac[2] {};
    int32_t mac[2] {};

    int32_t dcHit = 0;
    int32_t mcHit = 0;
    int32_t dcDodge = 0;
    int32_t mcDodge = 0;
    int32_t speed = 0;
    int32_t comfort = 0;
    int32_t luckCurse = 0;

    int32_t dcElem[7] {};
    int32_t acElem[7] {};
    int32_t load[3] {};
    uint8_t doubleHand = 0;
    uint8_t weaponSound = 7;
    uint8_t mine = 0;
    uint8_t metaReserved = 0;
};

struct ItemDetailRecord
{
    uint32_t itemID = 0;
    int32_t duration = 0;
    int32_t hp[3] {};
    int32_t mp[3] {};
    int32_t req[4] {};
};

struct PotionEffectRecord
{
    uint32_t itemID = 0;
    uint32_t buffID = 0;
    uint32_t flags = 0; // bit0 stackReplace, bit1 unsupported acts, bit2 missing buff
    int32_t hp[2] {}; // flat value, percentage of maximum
    int32_t mp[2] {};
    int32_t hpPulse[4] {}; // flat, percentage, duration(ms), triggers per second
    int32_t mpPulse[4] {};
};

struct SkillMetaRecord
{
    uint32_t magicID = 0;
    uint32_t iconID = 0;
    int32_t coolDown = 0;
    uint8_t page = 0;
    uint8_t x = 0;
    uint8_t y = 0;
    uint8_t flags = 0;
};

struct BuffMetaRecord
{
    uint32_t buffID = 0;
    uint32_t iconID = 0;
    int8_t favor = 0;
    uint8_t reserved[3] {};
};

struct MagicEffectMetaRecord
{
    uint32_t magicID = 0;
    uint32_t gfxID = 0;
    uint32_t modColor = 0;
    uint16_t frameCount = 0;
    uint16_t gfxIDCount = 0;
    uint16_t speed = 0;
    uint8_t stage = 0;
    uint8_t type = 0;
    uint8_t gfxDirType = 0;
    uint8_t flags = 0;
    uint32_t seffID = UINT32_MAX;
    std::array<int16_t, 32> targetOff {};
    uint8_t motion = 0;
};
#pragma pack(pop)

static_assert(sizeof(MapHeader) == 28);
static_assert(sizeof(TileRecord) == 8);
static_assert(sizeof(ObjectRecord) == 12);
static_assert(sizeof(SpriteHeader) == 12);
static_assert(sizeof(SpriteRecord) == 8);
static_assert(sizeof(MonsterMetaRecord) == 68);
static_assert(sizeof(ItemMetaRecord) == 156);
static_assert(sizeof(ItemDetailRecord) == 48);
static_assert(sizeof(PotionEffectRecord) == 60);
static_assert(sizeof(SkillMetaRecord) == 16);
static_assert(sizeof(BuffMetaRecord) == 12);
static_assert(sizeof(MagicEffectMetaRecord) == 91);

static uint32_t monsterSeffID(std::u8string_view monsterName, int offset)
{
    const auto &record = DBCOM_MONSTERRECORD(monsterName.data());
    fflassert(record);
    if(!record.seff.ref.empty()){
        return monsterSeffID(record.seff.ref, offset);
    }
    if(const auto &entry = record.seff.list.at(offset); entry.has_value()){
        const auto &[subname, absoluteID] = entry.value();
        return subname.empty() ? absoluteID : monsterSeffID(subname, offset);
    }
    return SYS_MONSEFFBASE(record.lookID) + offset;
}

static MonsterMetaRecord monsterMetaRecord(uint32_t monsterID)
{
    const auto &record = DBCOM_MONSTERRECORD(monsterID);
    fflassert(record);
    const auto deathEffectName = std::u8string(record.name) + u8"_死亡特效";

    MonsterMetaRecord result
    {
        .monsterID = monsterID,
        .lookID = check_cast<uint16_t>(record.lookID),
        .shadow = to_u8(record.shadow),
        .reserved = to_u8(record.deadFadeOut),
        .spawnSeffID = monsterSeffID(record.name, MONSEFF_SPAWN),
        .attackSeffID = monsterSeffID(record.name, MONSEFF_ATTACK),
        .hittedSeffID = monsterSeffID(record.name, MONSEFF_HITTED),
        .dieSeffID = monsterSeffID(record.name, MONSEFF_DIE),
        .spawnLookID = check_cast<uint16_t>(std::u8string_view(record.name) == u8"神兽" ? 0X59 : 0),
        .deathMagicID = DBCOM_MAGICID(deathEffectName.c_str()),
        .attackMotionMagicID = std::u8string_view(record.name) == u8"霸王教主" ? DBCOM_MAGICID(u8"霸王教主_火刃") : 0,
        .transformEffectMagicID = std::u8string_view(record.name) == u8"祖玛教主" ? DBCOM_MAGICID(u8"祖玛教主_石像碎片") : 0,
        .spawnEffectMagicID = std::u8string_view(record.name) == u8"僧侣僵尸" ? DBCOM_MAGICID(u8"僧侣僵尸_地洞")
                             : std::u8string_view(record.name) == u8"沙漠石人" ? DBCOM_MAGICID(u8"沙漠石人_石坑") : 0,
        .behaveMode = check_cast<uint8_t>(record.behaveMode),
    };

    // transfFlags: bit 0/1 reverse active/hidden transform, bit 2 hidden
    // form can be focused, bit 3 transformation uses DIR_BEGIN, bit 4
    // ACTION_HITTED forces an active-form transformation.
    const auto setTransf = [&result](uint16_t hiddenLook, int standMotion, int standBegin, int standCount,
                                    int activeMotion, int activeBegin, int activeCount,
                                    int hiddenMotion, int hiddenBegin, int hiddenCount, int flags, int motionFlags)
    {
        result.hiddenLookID = hiddenLook;
        result.hiddenStandMotion = check_cast<uint8_t>(standMotion);
        result.hiddenStandBegin = check_cast<uint8_t>(standBegin);
        result.hiddenStandCount = check_cast<uint8_t>(standCount);
        result.activeTransfMotion = check_cast<uint8_t>(activeMotion);
        result.activeTransfBegin = check_cast<uint8_t>(activeBegin);
        result.activeTransfCount = check_cast<uint8_t>(activeCount);
        result.hiddenTransfMotion = check_cast<uint8_t>(hiddenMotion);
        result.hiddenTransfBegin = check_cast<uint8_t>(hiddenBegin);
        result.hiddenTransfCount = check_cast<uint8_t>(hiddenCount);
        result.transfFlags = check_cast<uint8_t>(flags);
        result.motionCorrectionFlags = check_cast<uint8_t>(motionFlags);
    };

    const std::u8string_view name = record.name;
    if(name == u8"食人花"){
        setTransf(0, 8, 7, 1, 8, 7, 8, 8, 0, 8, 0X09, 0X00);
    }
    else if(name == u8"触龙神"){
        setTransf(0, 8, 0, 1, 8, 0, 10, 8, 9, 10, 0X1A, 0X00);
    }
    else if(name == u8"僵尸_1" || name == u8"僵尸_2" || name == u8"腐僵"){
        setTransf(0, 4, 9, 1, 8, 0, 10, 4, 0, 10, 0X00, 0X00);
    }
    else if(name == u8"沙鬼"){
        setTransf(0, 8, 9, 1, 8, 9, 10, 8, 0, 10, 0X01, 0X00);
    }
    else if(name == u8"神兽"){
        setTransf(0X59, 0, 0, 4, 8, 0, 10, 8, 9, 10, 0X06, 0X03);
    }
    else if(name == u8"祖玛雕像" || name == u8"祖玛卫士"){
        setTransf(0, 8, 0, 1, 8, 0, 6, 8, 5, 6, 0X02, 0X02);
    }
    else if(name == u8"祖玛教主"){
        // The C++ hidden-form branch returns an empty spawn sequence after the
        // mode trigger flips. Use the symmetric reverse sequence so burrowing
        // remains visible and completes instead of leaving a zero-frame motion.
        setTransf(0, 8, 0, 1, 8, 0, 10, 8, 9, 10, 0X0A, 0X02);
    }

    // bodyFlags: bit 0 redirects every non-hitted body motion to stand,
    // bit 1 forces the first graphics direction.
    if(name == u8"爆裂蜘蛛"){
        result.bodyStandMotionID = 1;
        result.bodyStandFrameCount = 1;
    }
    else if(name == u8"诺玛大法老"){
        result.bodyAttackMotionID = 6;
        result.bodyAttackFrameCount = 6;
    }
    else if(name == u8"沙漠树魔"){
        result.bodyStandFrameCount = 1;
        result.bodyAttackMotionID = 2;
        result.bodyAttackFrameCount = 10;
    }
    else if(name == u8"霸王教主"){
        result.bodyAttackMotionID = 2;
        result.bodyAttackFrameCount = 10;
        result.bodyAltAttackMagicID = DBCOM_MAGICID(u8"霸王教主_野蛮冲撞");
        result.bodyAltAttackMotionID = 6;
        result.bodyAltAttackFrameCount = 10;
    }
    else if(name == u8"角蝇"){
        result.bodyFlags = 0X02;
    }
    else if(name == u8"栗子树" || name == u8"圣诞树" || name == u8"圣诞树1"){
        result.bodyStandFrameCount = 4;
        result.bodyFlags = 0X03;
    }
    else if(name == u8"变异骷髅" || name == u8"超强骷髅"){
        result.spawnDirection = DIR_DOWNLEFT;
    }
    return result;
}

static uint8_t weaponSoundID(std::u8string_view category)
{
    if(category == u8"匕首") return 0;
    if(category == u8"木剑") return 1;
    if(category == u8"剑"  ) return 2;
    if(category == u8"刀"  ) return 3;
    if(category == u8"斧"  ) return 4;
    if(category == u8"锏"  ) return 5;
    if(category == u8"棍"  ) return 6;
    return 7;
}

static bool animatedTextureSet(uint32_t textureID)
{
    switch(textureID >> 16){
        case 11:
        case 26:
        case 41:
        case 56:
        case 71:
            return true;
        default:
            return false;
    }
}

template<typename T> static void writeVector(std::ofstream &ofs, const std::vector<T> &data)
{
    if(!data.empty()){
        ofs.write(reinterpret_cast<const char *>(data.data()), static_cast<std::streamsize>(data.size() * sizeof(T)));
    }
}

static std::string mapBinName(uint32_t mapID)
{
    const auto &record = DBCOM_MAPRECORD(mapID);
    if(!record){
        return {};
    }
    const std::string mapName = to_cstr(record.name);
    if(const auto pos = mapName.find('_'); pos != std::string::npos && pos + 1 < mapName.size()){
        return mapName.substr(pos + 1) + ".bin";
    }
    return {};
}

static void extractTexture(ZSDB &textureDB, uint32_t textureID, const fs::path &textureDir)
{
    if(g_noPNG){
        return;
    }
    char key[16] {};
    const auto keyString = hexstr::to_string<uint32_t, 4>(textureID, key, true);
    const auto outputPath = textureDir / (std::string(keyString, 8) + ".png");
    if(fs::exists(outputPath)){
        return;
    }

    std::vector<uint8_t> pngData;
    if(!textureDB.decomp(keyString, 8, &pngData)){
        throw fflpanic("missing map texture: 0x{:08X}", textureID);
    }
    std::ofstream ofs(outputPath, std::ios::binary);
    writeVector(ofs, pngData);
    if(!ofs){
        throw fflpanic("failed to write texture: {}", outputPath.string());
    }
}

static size_t convertMap(uint32_t mapID, ZSDB &mapDB, ZSDB &textureDB, const fs::path &outputDir)
{
    const auto binName = mapBinName(mapID);
    if(binName.empty()){
        return 0;
    }

    std::vector<uint8_t> mapDataBuf;
    if(!mapDB.decomp(binName.c_str(), 0, &mapDataBuf)){
        std::fprintf(stderr, "skip map %u: missing %s\n", mapID, binName.c_str());
        return 0;
    }
    const Mir2xMapData mapData(mapDataBuf.data(), mapDataBuf.size());

    std::vector<uint8_t> landList(mapData.w() * mapData.h());
    std::vector<TileRecord> tileList;
    std::vector<ObjectRecord> objectList;
    std::unordered_set<uint32_t> textureSet;

    for(size_t y = 0; y < mapData.h(); ++y){
        for(size_t x = 0; x < mapData.w(); ++x){
            const auto &cell = mapData.cell(to_d(x), to_d(y));
            landList[x + y * mapData.w()] = to_u8(cell.land.type | (cell.land.canFly << 6) | (cell.land.canWalk << 7));

            if(!(x % 2) && !(y % 2)){
                const auto &tile = mapData.tile(to_d(x), to_d(y));
                if(tile.valid){
                    tileList.push_back({to_u16(x), to_u16(y), tile.texID});
                    textureSet.insert(tile.texID);
                }
            }

            for(const auto &object: cell.obj){
                if(!object.valid){
                    continue;
                }
                objectList.push_back({
                    to_u16(x),
                    to_u16(y),
                    object.texID,
                    to_u8(object.depth),
                    to_u8((object.animated ? 1 : 0) | (object.alpha ? 2 : 0)),
                    to_u8(object.tickType),
                    to_u8(object.frameCount),
                });
                textureSet.insert(object.texID);
                if(object.animated && animatedTextureSet(object.texID)){
                    for(uint32_t frame = 1; frame < object.frameCount; ++frame){
                        textureSet.insert(object.texID + frame);
                    }
                }
            }
        }
    }

    const auto mapDir = outputDir / "maps";
    const auto textureDir = outputDir / "textures";
    fs::create_directories(mapDir);
    fs::create_directories(textureDir);

    const MapHeader header {
        .mapID = mapID,
        .width = to_u32(mapData.w()),
        .height = to_u32(mapData.h()),
        .tileCount = to_u32(tileList.size()),
        .objectCount = to_u32(objectList.size()),
    };
    const auto mapPath = mapDir / str_printf("%08X.m2xmap", mapID);
    std::ofstream ofs(mapPath, std::ios::binary);
    ofs.write(reinterpret_cast<const char *>(&header), sizeof(header));
    writeVector(ofs, landList);
    writeVector(ofs, tileList);
    writeVector(ofs, objectList);
    if(!ofs){
        throw fflpanic("failed to write map: {}", mapPath.string());
    }

    const auto metaPath = mapDir / str_printf("%08X.m2xmeta", mapID);
    std::ofstream metaFile(metaPath, std::ios::binary);
    const auto &mapRecord = DBCOM_MAPRECORD(mapID);
    const uint32_t miniMapID = mapRecord.miniMapID.value_or(UINT32_MAX);
    metaFile.write(reinterpret_cast<const char *>(&miniMapID), sizeof(miniMapID));
    std::string displayName(to_cstr(mapRecord.name));
    if(const auto pos = displayName.find('_'); pos != std::string::npos){
        displayName.resize(pos);
    }
    const auto nameLength = check_cast<uint16_t>(displayName.size());
    metaFile.write(reinterpret_cast<const char *>(&nameLength), sizeof(nameLength));
    metaFile.write(displayName.data(), nameLength);
    const uint32_t bgmID = mapRecord.bgmID.value_or(UINT32_MAX);
    metaFile.write(reinterpret_cast<const char *>(&bgmID), sizeof(bgmID));
    if(!metaFile){
        throw fflpanic("failed to write map metadata: {}", metaPath.string());
    }

    for(const auto textureID: textureSet){
        extractTexture(textureDB, textureID, textureDir);
    }

    std::printf("map %u: %zux%zu, %zu tiles, %zu objects, %zu textures\n", mapID, mapData.w(), mapData.h(), tileList.size(), objectList.size(), textureSet.size());
    return textureSet.size();
}

static size_t convertSprites(const char *family, const char *dbPath, const fs::path &outputDir)
{
    ZSDB db(dbPath);
    const auto spriteDir = outputDir / "sprites" / family;
    fs::create_directories(spriteDir);

    std::vector<SpriteRecord> spriteList;
    std::vector<uint8_t> pngData;
    for(const auto &entry: db.getEntryList()){
        if(!(entry.fileName && std::strlen(entry.fileName) >= 8)){
            continue;
        }
        const auto key = hexstr::to_hex<uint32_t, 4>(entry.fileName);
        const bool hasOffset = std::strlen(entry.fileName) >= 18;
        const int dx = hasOffset ? (entry.fileName[8] != '0' ? 1 : -1) * to_d(hexstr::to_hex<uint32_t, 2>(entry.fileName + 10)) : 0;
        const int dy = hasOffset ? (entry.fileName[9] != '0' ? 1 : -1) * to_d(hexstr::to_hex<uint32_t, 2>(entry.fileName + 14)) : 0;
        spriteList.push_back({key, check_cast<int16_t>(dx), check_cast<int16_t>(dy)});

        const auto outputPath = spriteDir / str_printf("%08X.png", key);
        if(!g_noPNG && !fs::exists(outputPath)){
            if(!db.decomp(entry.fileName, 0, &pngData)){
                throw fflpanic("failed to extract sprite: {}", entry.fileName);
            }
            std::ofstream ofs(outputPath, std::ios::binary);
            writeVector(ofs, pngData);
        }
    }

    const auto indexPath = outputDir / "sprites" / (std::string(family) + ".m2xindex");
    std::ofstream ofs(indexPath, std::ios::binary);
    const SpriteHeader header {.spriteCount = to_u32(spriteList.size())};
    ofs.write(reinterpret_cast<const char *>(&header), sizeof(header));
    writeVector(ofs, spriteList);
    if(!ofs){
        throw fflpanic("failed to write sprite index: {}", indexPath.string());
    }

    if(std::strcmp(family, "monster") == 0){
        std::vector<MonsterMetaRecord> metaList;
        for(uint32_t monsterID = 1; monsterID < DBCOM_MONSTERENDID(); ++monsterID){
            const auto &record = DBCOM_MONSTERRECORD(monsterID);
            if(record.name){
                metaList.push_back(monsterMetaRecord(monsterID));
            }
        }
        std::ofstream metaFile(outputDir / "sprites" / "monster.m2xmeta", std::ios::binary);
        const SpriteHeader metaHeader {.version = 12, .spriteCount = to_u32(metaList.size())};
        metaFile.write(reinterpret_cast<const char *>(&metaHeader), sizeof(metaHeader));
        writeVector(metaFile, metaList);

        std::ofstream nameFile(outputDir / "sprites" / "monster_name.m2xmeta", std::ios::binary);
        const SpriteHeader nameHeader {.spriteCount = to_u32(metaList.size())};
        nameFile.write(reinterpret_cast<const char *>(&nameHeader), sizeof(nameHeader));
        for(const auto &meta: metaList){
            const std::string name(to_cstr(DBCOM_MONSTERRECORD(meta.monsterID).name));
            const auto length = check_cast<uint16_t>(name.size());
            nameFile.write(reinterpret_cast<const char *>(&meta.monsterID), sizeof(meta.monsterID));
            nameFile.write(reinterpret_cast<const char *>(&length), sizeof(length));
            nameFile.write(name.data(), length);
        }
    }
    if(std::strcmp(family, "hero") == 0){
        constexpr std::array<uint8_t, 2640> weaponOrder
        {
            #include "weaponorder.inc"
        };
        std::ofstream weaponOrderFile(outputDir / "sprites" / "weapon_order.m2xmeta", std::ios::binary);
        const SpriteHeader weaponOrderHeader {.spriteCount = to_u32(weaponOrder.size())};
        weaponOrderFile.write(reinterpret_cast<const char *>(&weaponOrderHeader), sizeof(weaponOrderHeader));
        weaponOrderFile.write(reinterpret_cast<const char *>(weaponOrder.data()), static_cast<std::streamsize>(weaponOrder.size()));
        if(!weaponOrderFile){
            throw fflpanic("failed to write hero weapon order metadata");
        }

        std::vector<ItemMetaRecord> metaList;
        for(uint32_t itemID = 1; itemID < DBCOM_ITEMENDID(); ++itemID){
            const auto &record = DBCOM_ITEMRECORD(itemID);
            if(record.name){
                metaList.push_back({
                    .itemID = itemID,
                    .shape = check_cast<uint16_t>(record.shape),
                    .reserved = to_u16(record.packable()),
                    .pkgGfxID = check_cast<uint32_t>(record.pkgGfxID),
                    .weight = record.weight,
                    .dc = {record.equip.dc[0], record.equip.dc[1]},
                    .mc = {record.equip.mc[0], record.equip.mc[1]},
                    .sc = {record.equip.sc[0], record.equip.sc[1]},
                    .ac = {record.equip.ac[0], record.equip.ac[1]},
                    .mac = {record.equip.mac[0], record.equip.mac[1]},
                    .dcHit = record.equip.dcHit,
                    .mcHit = record.equip.mcHit,
                    .dcDodge = record.equip.dcDodge,
                    .mcDodge = record.equip.mcDodge,
                    .speed = record.equip.speed,
                    .comfort = record.equip.comfort,
                    .luckCurse = record.equip.luckCurse,
                    .dcElem = {
                        record.equip.dcElem.fire, record.equip.dcElem.ice, record.equip.dcElem.light,
                        record.equip.dcElem.wind, record.equip.dcElem.holy, record.equip.dcElem.dark,
                        record.equip.dcElem.phantom,
                    },
                    .acElem = {
                        record.equip.acElem.fire, record.equip.acElem.ice, record.equip.acElem.light,
                        record.equip.acElem.wind, record.equip.acElem.holy, record.equip.acElem.dark,
                        record.equip.acElem.phantom,
                    },
                    .load = {record.equip.load.body, record.equip.load.weapon, record.equip.load.inventory},
                    .doubleHand = to_u8(record.equip.weapon.doubleHand),
                    .weaponSound = weaponSoundID(record.equip.weapon.category),
                    .mine = to_u8(record.equip.weapon.mine),
                });
            }
        }
        std::ofstream metaFile(outputDir / "sprites" / "item.m2xmeta", std::ios::binary);
        const SpriteHeader metaHeader {.version = 5, .spriteCount = to_u32(metaList.size())};
        metaFile.write(reinterpret_cast<const char *>(&metaHeader), sizeof(metaHeader));
        writeVector(metaFile, metaList);

        const SpriteHeader textMetaHeader {.spriteCount = to_u32(metaList.size())};
        std::ofstream nameFile(outputDir / "sprites" / "item_name.m2xmeta", std::ios::binary);
        nameFile.write(reinterpret_cast<const char *>(&textMetaHeader), sizeof(textMetaHeader));
        std::ofstream typeFile(outputDir / "sprites" / "item_type.m2xmeta", std::ios::binary);
        typeFile.write(reinterpret_cast<const char *>(&textMetaHeader), sizeof(textMetaHeader));
        for(const auto &meta: metaList){
            const std::string name(to_cstr(DBCOM_ITEMRECORD(meta.itemID).name));
            const auto length = check_cast<uint16_t>(name.size());
            nameFile.write(reinterpret_cast<const char *>(&meta.itemID), sizeof(meta.itemID));
            nameFile.write(reinterpret_cast<const char *>(&length), sizeof(length));
            nameFile.write(name.data(), length);

            const std::string type(to_cstr(DBCOM_ITEMRECORD(meta.itemID).type));
            const auto typeLength = check_cast<uint16_t>(type.size());
            typeFile.write(reinterpret_cast<const char *>(&meta.itemID), sizeof(meta.itemID));
            typeFile.write(reinterpret_cast<const char *>(&typeLength), sizeof(typeLength));
            typeFile.write(type.data(), typeLength);
        }

        // Player::consumePotion uses the same-name BuffRecord, not ir.potion.
        // Keep actual backend effects separate from nominal item attributes.
        std::vector<PotionEffectRecord> potionEffects;
        for(const auto &meta: metaList){
            const auto &ir = DBCOM_ITEMRECORD(meta.itemID);
            if(!ir.isPotion()){
                continue;
            }
            PotionEffectRecord effect;
            effect.itemID = meta.itemID;
            effect.buffID = DBCOM_BUFFID(ir.name);
            const auto &buff = DBCOM_BUFFRECORD(effect.buffID);
            if(!buff){
                effect.flags |= 4;
            }
            else{
                effect.flags |= buff.stackReplace ? 1 : 0;
                uint32_t seen = 0;
                for(const auto &act: buff.actList){
                    const bool hp = act.isBuffActRef(u8"HP");
                    const bool mp = act.isBuffActRef(u8"MP");
                    const bool hpPulse = act.isBuffActRef(u8"HP持续");
                    const bool mpPulse = act.isBuffActRef(u8"MP持续");
                    const uint32_t bit = hp ? 1 : mp ? 2 : hpPulse ? 4 : mpPulse ? 8 : 0;
                    const auto &arg = (hp || mp) ? act.attributeModifier.arg : act.trigger.arg;
                    const auto value = std::get_if<BuffValuePercentage>(&arg);
                    if(!bit || (seen & bit) || !value || ((hpPulse || mpPulse) && (!(act.trigger.on & BATGR_TIME) || act.trigger.tps <= 0))){
                        effect.flags |= 2;
                        continue;
                    }
                    seen |= bit;
                    auto out = hp ? effect.hp : mp ? effect.mp : hpPulse ? effect.hpPulse : effect.mpPulse;
                    out[0] = value->value;
                    out[1] = value->percentage;
                    if(hpPulse || mpPulse){
                        out[2] = act.duration;
                        out[3] = act.trigger.tps;
                    }
                }
            }
            potionEffects.push_back(effect);
        }
        std::ofstream potionFile(outputDir / "sprites" / "potion_effect.m2xmeta", std::ios::binary);
        const SpriteHeader potionHeader {{'M', '2', 'S', 'P'}, 1, check_cast<uint32_t>(potionEffects.size())};
        potionFile.write(reinterpret_cast<const char *>(&potionHeader), sizeof(potionHeader));
        potionFile.write(reinterpret_cast<const char *>(potionEffects.data()), potionEffects.size() * sizeof(PotionEffectRecord));
        if(!potionFile){
            throw fflpanic("failed to write potion effect metadata");
        }

        std::ofstream detailFile(outputDir / "sprites" / "item_detail.m2xmeta", std::ios::binary);
        detailFile.write(reinterpret_cast<const char *>(&textMetaHeader), sizeof(textMetaHeader));
        for(const auto &meta: metaList){
            const auto &record = DBCOM_ITEMRECORD(meta.itemID);
            const ItemDetailRecord detail
            {
                .itemID = meta.itemID,
                .duration = record.equip.duration,
                .hp = {record.equip.hp.add, record.equip.hp.steal, record.equip.hp.recover},
                .mp = {record.equip.mp.add, record.equip.mp.steal, record.equip.mp.recover},
                .req = {record.equip.req.dc, record.equip.req.mc, record.equip.req.sc, record.equip.req.level},
            };
            detailFile.write(reinterpret_cast<const char *>(&detail), sizeof(detail));

            const std::string description = str_haschar(record.description) ? to_cstr(record.description) : "";
            const auto descriptionLength = check_cast<uint16_t>(description.size());
            detailFile.write(reinterpret_cast<const char *>(&descriptionLength), sizeof(descriptionLength));
            detailFile.write(description.data(), descriptionLength);

            const std::string job = str_haschar(record.equip.req.job) ? to_cstr(record.equip.req.job) : "";
            const auto jobLength = check_cast<uint16_t>(job.size());
            detailFile.write(reinterpret_cast<const char *>(&jobLength), sizeof(jobLength));
            detailFile.write(job.data(), jobLength);
        }
    }
    if(std::strcmp(family, "proguse") == 0){
        std::vector<SkillMetaRecord> metaList;
        for(const auto &gfx: SkillBoardData::m_iconGfxList){
            const auto &record = DBCOM_MAGICRECORD(gfx.magicID);
            if(!record){
                continue;
            }
            const auto elemID = magicElemID(record.elem);
            const int page = elemID == MET_NONE
                           ? 7
                           : (elemID >= MET_BEGIN && elemID < MET_END ? elemID - MET_BEGIN : -1);
            if(page < 0){
                continue;
            }
            metaList.push_back({
                gfx.magicID,
                gfx.magicIcon,
                record.coolDown,
                check_cast<uint8_t>(page),
                check_cast<uint8_t>(gfx.x),
                check_cast<uint8_t>(gfx.y),
                to_u8(gfx.passive),
            });
        }
        std::ofstream metaFile(outputDir / "sprites" / "skill.m2xmeta", std::ios::binary);
        const SpriteHeader metaHeader {.version = 2, .spriteCount = to_u32(metaList.size())};
        metaFile.write(reinterpret_cast<const char *>(&metaHeader), sizeof(metaHeader));
        writeVector(metaFile, metaList);

        std::vector<BuffMetaRecord> buffList;
        for(uint32_t buffID = 1; buffID < DBCOM_BUFFENDID(); ++buffID){
            const auto &record = DBCOM_BUFFRECORD(buffID);
            if(record.name && record.icon.show && record.icon.gfxID != SYS_U32NIL){
                buffList.push_back({buffID, record.icon.gfxID, check_cast<int8_t>(record.favor)});
            }
        }
        std::ofstream buffFile(outputDir / "sprites" / "buff.m2xmeta", std::ios::binary);
        const SpriteHeader buffHeader {.spriteCount = to_u32(buffList.size())};
        buffFile.write(reinterpret_cast<const char *>(&buffHeader), sizeof(buffHeader));
        writeVector(buffFile, buffList);

        std::vector<uint32_t> namedBuffList;
        for(uint32_t buffID = 1; buffID < DBCOM_BUFFENDID(); ++buffID){
            if(str_haschar(DBCOM_BUFFRECORD(buffID).name)){
                namedBuffList.push_back(buffID);
            }
        }
        std::ofstream buffNameFile(outputDir / "sprites" / "buff_name.m2xmeta", std::ios::binary);
        const SpriteHeader buffNameHeader {.spriteCount = to_u32(namedBuffList.size())};
        buffNameFile.write(reinterpret_cast<const char *>(&buffNameHeader), sizeof(buffNameHeader));
        for(const auto buffID: namedBuffList){
            const std::string name(to_cstr(DBCOM_BUFFRECORD(buffID).name));
            const auto length = check_cast<uint16_t>(name.size());
            buffNameFile.write(reinterpret_cast<const char *>(&buffID), sizeof(buffID));
            buffNameFile.write(reinterpret_cast<const char *>(&length), sizeof(length));
            buffNameFile.write(name.data(), length);
        }
    }
    if(std::strcmp(family, "magic") == 0){
        std::vector<MagicEffectMetaRecord> metaList;
        std::vector<MagicEffectMetaRecord> loopMetaList;
        for(uint32_t magicID = 1; magicID < DBCOM_MAGICENDID(); ++magicID){
            const auto &record = DBCOM_MAGICRECORD(magicID);
            if(!record){
                continue;
            }
            for(int stage = MST_BEGIN; stage < MST_END; ++stage){
                const auto [gfxEntry, gfxRef] = DBCOM_MAGICGFXENTRY(magicID, magicStageName(stage));
                if(!gfxEntry){
                    continue;
                }
                metaList.push_back({
                    magicID,
                    gfxEntry->gfxID,
                    gfxRef ? gfxRef->modColor : gfxEntry->modColor,
                    check_cast<uint16_t>(gfxEntry->frameCount),
                    check_cast<uint16_t>(gfxEntry->gfxIDCount),
                    check_cast<uint16_t>(gfxEntry->speed),
                    check_cast<uint8_t>(stage),
                    check_cast<uint8_t>(magicGfxEntryID(gfxEntry->type)),
                    check_cast<uint8_t>(gfxEntry->gfxDirType),
                    to_u8((gfxEntry->loop ? 1 : 0) | (gfxEntry->onGround ? 2 : 0) | ((gfxEntry->gfxID == SYS_U32NIL || gfxEntry->frameCount <= 0) ? 4 : 0)),
                    DBCOM_MAGICGFXSEFFID(magicID, magicStageName(stage)).value_or(UINT32_MAX),
                });
                auto &meta = metaList.back();
                meta.motion = check_cast<uint8_t>(gfxEntry->motion);
                size_t direction = 0;
                for(const auto &[targetOffX, targetOffY]: gfxEntry->targetOffList){
                    fflassert(direction < 16);
                    meta.targetOff[direction * 2 + 0] = check_cast<int16_t>(targetOffX);
                    meta.targetOff[direction * 2 + 1] = check_cast<int16_t>(targetOffY);
                    ++direction;
                }
                // A stage can have an intro followed by a separate looping range.
                // DBCOM_MAGICGFXENTRY returns only the first stage entry.
                for(const auto &continuation: record.gfxList){
                    if(!continuation || !continuation.loop || &continuation == gfxEntry || !continuation.checkStage(magicStageName(stage))){
                        continue;
                    }
                    MagicEffectMetaRecord loopMeta {
                        magicID,
                        continuation.gfxID,
                        continuation.modColor,
                        check_cast<uint16_t>(continuation.frameCount),
                        check_cast<uint16_t>(continuation.gfxIDCount),
                        check_cast<uint16_t>(continuation.speed),
                        check_cast<uint8_t>(stage),
                        check_cast<uint8_t>(magicGfxEntryID(continuation.type)),
                        check_cast<uint8_t>(continuation.gfxDirType),
                        to_u8(1 | (continuation.onGround ? 2 : 0) | ((continuation.gfxID == SYS_U32NIL || continuation.frameCount <= 0) ? 4 : 0)),
                        UINT32_MAX,
                    };
                    loopMeta.motion = check_cast<uint8_t>(continuation.motion);
                    size_t loopDirection = 0;
                    for(const auto &[targetOffX, targetOffY]: continuation.targetOffList){
                        fflassert(loopDirection < 16);
                        loopMeta.targetOff[loopDirection * 2 + 0] = check_cast<int16_t>(targetOffX);
                        loopMeta.targetOff[loopDirection * 2 + 1] = check_cast<int16_t>(targetOffY);
                        ++loopDirection;
                    }
                    loopMetaList.push_back(loopMeta);
                    break;
                }
            }
        }
        std::ofstream metaFile(outputDir / "sprites" / "magic.m2xmeta", std::ios::binary);
        const SpriteHeader metaHeader {.version = 5, .spriteCount = to_u32(metaList.size())};
        metaFile.write(reinterpret_cast<const char *>(&metaHeader), sizeof(metaHeader));
        writeVector(metaFile, metaList);

        std::ofstream loopFile(outputDir / "sprites" / "magic_loop.m2xmeta", std::ios::binary);
        const SpriteHeader loopHeader {.version = 5, .spriteCount = to_u32(loopMetaList.size())};
        loopFile.write(reinterpret_cast<const char *>(&loopHeader), sizeof(loopHeader));
        writeVector(loopFile, loopMetaList);

        std::ofstream nameFile(outputDir / "sprites" / "magic_name.m2xmeta", std::ios::binary);
        uint32_t nameCount = 0;
        for(uint32_t magicID = 1; magicID < DBCOM_MAGICENDID(); ++magicID){
            nameCount += DBCOM_MAGICRECORD(magicID) ? 1 : 0;
        }
        const SpriteHeader nameHeader {.spriteCount = nameCount};
        nameFile.write(reinterpret_cast<const char *>(&nameHeader), sizeof(nameHeader));
        for(uint32_t magicID = 1; magicID < DBCOM_MAGICENDID(); ++magicID){
            if(!DBCOM_MAGICRECORD(magicID)){
                continue;
            }
            const std::string name(to_cstr(DBCOM_MAGICRECORD(magicID).name));
            const auto length = check_cast<uint16_t>(name.size());
            nameFile.write(reinterpret_cast<const char *>(&magicID), sizeof(magicID));
            nameFile.write(reinterpret_cast<const char *>(&length), sizeof(length));
            nameFile.write(name.data(), length);
        }
    }
    std::printf("sprite family %s: %zu frames\n", family, spriteList.size());
    return spriteList.size();
}

int main(int argc, char *argv[])
{
    g_noPNG = consumeFlag(argc, argv, "--no-png");
    if(argc >= 5 && std::strcmp(argv[1], "--sprites") == 0 && (argc % 2 == 1)){
        const fs::path outputDir(argv[2]);
        size_t totalCount = 0;
        for(int index = 3; index + 1 < argc; index += 2){
            totalCount += convertSprites(argv[index], argv[index + 1], outputDir);
        }
        return totalCount ? 0 : 1;
    }
    if(argc != 4 && argc != 5){
		std::fprintf(stderr, "Usage: godotworldres mapbin.zsdb map.zsdb output-dir [map-id] [--no-png]\n");
		std::fprintf(stderr, "       godotworldres --sprites output-dir family sprite.zsdb [family sprite.zsdb ...] [--no-png]\n");
        return 2;
    }

    ZSDB mapDB(argv[1]);
    ZSDB textureDB(argv[2]);
    const fs::path outputDir(argv[3]);
    if(argc == 5){
        const auto mapID = check_cast<uint32_t>(std::stoul(argv[4]));
        return convertMap(mapID, mapDB, textureDB, outputDir) ? 0 : 1;
    }

    size_t mapCount = 0;
    for(uint32_t mapID = 1; mapID < DBCOM_MAPENDID(); ++mapID){
        if(convertMap(mapID, mapDB, textureDB, outputDir)){
            ++mapCount;
        }
    }
    std::printf("converted %zu maps\n", mapCount);
    return mapCount ? 0 : 1;
}
