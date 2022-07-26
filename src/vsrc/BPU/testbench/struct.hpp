#pragma once

struct __attribute__((packed)) tage_meta_t
{
    std::uint64_t data[2];
    std::uint64_t : 38;
};

struct __attribute__((packed)) bpu_ftq_meta_t
{
    std::uint64_t data[2];
    std::uint64_t : 38;
    bool ftb_hit : 1;
    bool valid : 1;
};

struct __attribute__((packed)) tage_predictor_update_info_t
{
    std::uint64_t data[2];
    std::uint64_t : 38;
    bool is_conditional : 1;
    bool branch_taken : 1;
    bool predict_correct : 1;
    bool valid : 1;
};
