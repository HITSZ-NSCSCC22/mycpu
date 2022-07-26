struct tage_meta_t
{
    unsigned int provider_id : 3;
    unsigned int alt_provider_id : 3;
    bool useful : 1;
    unsigned int : 159;
};

struct bpu_ftq_meta_t
{
    bool valid : 1;
    bool ftb_hit : 1;
    tage_meta_t tage_meta;
};

struct tage_predictor_update_info_t
{
    bool valid : 1;
    bool predict_correct : 1;
    bool branch_taken : 1;
    bool is_conditional : 1;
    tage_meta_t tage_meta;
};
