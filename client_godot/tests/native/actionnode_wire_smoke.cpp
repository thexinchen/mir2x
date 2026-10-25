#include <array>
#include <cstdio>
#include <cstring>
#include "actionnode.hpp"

int main()
{
    for(unsigned direction = 0; direction <= 8; ++direction){
        ActionNode node{};
        node.type = ACTION_ATTACK;
        node.speed = 100;
        node.direction = direction;
        node.x = -123;
        node.y = 456;
        node.aimX = 321;
        node.aimY = -654;
        node.aimUID = 0x0807060504030201ULL;
        node.extParam.attack.magicID = 24;
        std::array<unsigned char, 27> bytes{};
        std::memcpy(bytes.data(), &node, sizeof(node));
        // Independent literal bytes matching protocol.gd, not a bitfield round trip.
        const std::array<unsigned char, 27> expected = {
            0x87, 0x0c, static_cast<unsigned char>(direction),
            0x85, 0xff, 0xc8, 0x01, 0x41, 0x01, 0x72, 0xfd,
            1, 2, 3, 4, 5, 6, 7, 8, 24, 0, 0, 0, 0, 0, 0, 0};
        if(bytes != expected){
            std::fprintf(stderr, "ACTION WIRE FAIL: native encode direction=%u\n", direction);
            return 1;
        }
        ActionNode decoded{};
        std::memcpy(&decoded, expected.data(), sizeof(decoded));
        if(decoded.direction != direction || decoded.type != ACTION_ATTACK || decoded.speed != 100
                || decoded.x != -123 || decoded.y != 456 || decoded.aimX != 321 || decoded.aimY != -654
                || decoded.aimUID != 0x0807060504030201ULL || decoded.extParam.attack.magicID != 24){
            std::fprintf(stderr, "ACTION WIRE FAIL: Godot decode direction=%u\n", direction);
            return 1;
        }
    }
    std::puts("ACTION WIRE PASS: fixed 27 bytes, independent direction byte, signed positions, UID and magic ID in both directions");
}
