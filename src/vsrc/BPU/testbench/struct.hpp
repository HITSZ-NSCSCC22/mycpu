#pragma once

#define TAGE_META_BITS_SIZE (612)

struct __attribute__((packed)) tage_meta_t
{
    std::uint64_t data[9];
    std::uint64_t : 36;
};

struct __attribute__((packed)) bpu_ftq_meta_t
{
    std::uint64_t data[9];
    std::uint64_t : 36;
    bool ftb_hit : 1;
    bool valid : 1;
};

struct __attribute__((packed)) tage_predictor_update_info_t
{
    std::uint64_t data[9];
    std::uint64_t : 36;
    bool is_conditional : 1;
    bool branch_taken : 1;
    bool predict_correct : 1;
    bool valid : 1;
};
