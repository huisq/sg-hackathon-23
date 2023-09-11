module admin::tbc{

    //==============================================================================================
    // Dependencies
    //==============================================================================================

    use std::object;
    use std::signer;
    use aptos_framework::option;
    use aptos_token_objects::token;
    use aptos_token_objects::property_map;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account::{Self, SignerCapability};
    use std::string;
    use aptos_token_objects::collection;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{AptosCoin};
    use std::bcs;

    //==============================================================================================
    // Errors
    //==============================================================================================

    const SIGNER_NOT_ADMIN: u64 = 0;

    //==============================================================================================
    // Constants
    //==============================================================================================

    // Seed for resource account creation
    const SEED: vector<u8> = b"aptosvigilante";

    // Token collection information
    const COLLECTION_NAME: vector<u8> = b"Review collection name";
    const COLLECTION_DESCRIPTION: vector<u8> = b"Review collection description";
    const COLLECTION_URI: vector<u8> = b"Review collection uri";

    // Token information
    const TOKEN_DESCRIPTION: vector<u8> = b"Review token description";
    const TOKEN_NAME: vector<u8> = b"Review token name";
    const TOKEN_URI: vector<u8> = b"Review token uri";

    // property names for review token properties
    const PROPERTY_KEY_USER_ADDRESS: vector<u8> = b"user_address";
    const PROPERTY_KEY_REVIEW_HASH: vector<u8> = b"review_hash"; //contains review title, content, tags

    //==============================================================================================
    // Module Structs
    //==============================================================================================

    struct ReviewToken has key {
        // Used for editing the token data
        mutator_ref: token::MutatorRef,
        // Used for burning the token
        burn_ref: token::BurnRef,
        // USed for editing the token's property_map
        property_mutator_ref: property_map::MutatorRef
    }

    // struct Project has key {
    //     // Number of reviews
    //     no_of_reviews: u64,
    //     // simple_map of reviews (key: reviewer add, review_token)
    //     reviews: SimpleMap<address, ReviewToken>,
    //     // Total score
    //     total_score: u64
    // }

    /*
        Information to be used in the module
    */
    struct State has key {
        // signer cap of the module's resource account
        signer_cap: SignerCapability,
        // Events
        review_submitted_events: EventHandle<ReviewSubmitted>,
        review_deleted_events: EventHandle<ReviewDeleted>
    }

    //==============================================================================================
    // Event structs
    //==============================================================================================

    struct ReviewSubmitted has store, drop {
        // address of the account submitting the review
        reviewer: address,
        // token address of review
        review_token_address: address,
        // review hash
        review: vector<u8>,
        // timestamp
        timestamp: u64
    }

    struct ReviewDeleted has store, drop {
        // token address of review
        review_token_address: address,
        // address of the account owning the review
        reviewer: address,
        // timestamp
        timestamp: u64
    }

    //==============================================================================================
    // Functions
    //==============================================================================================

    /*
        Initializes the module by creating a resource account, registering with AptosCoin, creating
        the token collectiions, and setting up the State resource.
        @param account - signer representing the module publisher
    */
    fun init_module(admin: &signer) {
        assert_admin(signer::address_of(admin));
        let (resource_signer, resource_cap) = account::create_resource_account(admin, SEED);

        coin::register<AptosCoin>(&resource_signer);

        // Create an NFT collection with an unlimied supply and the following aspects:
        //          - name: COLLECTION_NAME
        //          - description: COLLECTION_DESCRIPTION
        //          - uri: COLLECTION_URI
        //          - royalty: no royalty
        collection::create_unlimited_collection(
            admin,
            string::utf8(COLLECTION_DESCRIPTION),
            string::utf8(COLLECTION_NAME),
            option::none(),
            string::utf8(COLLECTION_URI)
        );

        // Create the State global resource and move it to the admin account
        let state = State{
            signer_cap: resource_cap,
            review_submitted_events: account::new_event_handle<ReviewSubmitted>(admin),
            review_deleted_events: account::new_event_handle<ReviewDeleted>(admin)
        };
        move_to<State>(admin, state);
    }

    /*
    Mints a new ReviewToken for the reviewer account
    @param admin - admin signer
    @param reviewer - signer representing the account reviewing the project
*/
    public entry fun submit_review(
        reviewer: &signer,
        review_hash: vector<u8>
    ) acquires State {

        let state = borrow_global_mut<State>(@admin);
        let res_signer = account::create_signer_with_capability(&state.signer_cap);

        // Create a new named token:
        let token_const_ref = token::create_named_token(
            &res_signer,
            string::utf8(COLLECTION_NAME),
            string::utf8(TOKEN_DESCRIPTION),
            string::utf8(TOKEN_NAME),
            option::none(),
            string::utf8(TOKEN_URI)
        );

        let obj_signer = object::generate_signer(&token_const_ref);

        // Transfer the token to the reviewer account
        object::transfer_raw(&res_signer, object::address_from_constructor_ref(&token_const_ref), signer::address_of(reviewer));

        // Create the property_map for the new token with the following properties:
        let prop_keys = vector[
            string::utf8(PROPERTY_KEY_USER_ADDRESS),
            string::utf8(PROPERTY_KEY_REVIEW_HASH),
        ];

        let prop_types = vector[
            string::utf8(b"address"),
            string::utf8(b"vector<u8>"),
        ];

        let prop_values = vector[
            bcs::to_bytes(&signer::address_of(reviewer)),
            bcs::to_bytes(&review_hash)
        ];

        let token_prop_map = property_map::prepare_input(prop_keys,prop_types,prop_values);
        property_map::init(&token_const_ref,token_prop_map);

        // Create the ReviewToken object and move it to the new token object signer
        let new_review_token = ReviewToken{
            mutator_ref: token::generate_mutator_ref(&token_const_ref),
            burn_ref: token::generate_burn_ref(&token_const_ref),
            property_mutator_ref: property_map::generate_mutator_ref(&token_const_ref),
        };

        move_to(&obj_signer, new_review_token);

        // Emit a new ReviewSubmittedEvent
        event::emit_event<ReviewSubmitted>(
            &mut state.review_submitted_events,
            ReviewSubmitted{
                reviewer: signer::address_of(reviewer),
                review_token_address: object::address_from_constructor_ref(&token_const_ref),
                review: review_hash,
                timestamp: timestamp::now_seconds()
            });
    }

    public entry fun delete_review(
        admin: &signer,
        review_token_address: address
    ) acquires State, ReviewToken {
        assert_admin(signer::address_of(admin));
        let review_token_object = object::address_to_object<ReviewToken>(review_token_address);
        let reviewer = object::owner(review_token_object);
        let review_token = move_from<ReviewToken>(review_token_address);
        let ReviewToken{mutator_ref: _, burn_ref, property_mutator_ref} = review_token;

        // Burn the token's property_map and the token
        property_map::burn(property_mutator_ref);
        token::burn(burn_ref);

        // Emit a new ReviewDeletedEvent
        let state = borrow_global_mut<State>(@admin);
        event::emit_event<ReviewDeleted>(
            &mut state.review_deleted_events,
            ReviewDeleted{
                review_token_address,
                reviewer,
                timestamp: timestamp::now_seconds()
            });
    }

    //==============================================================================================
    // Helper functions
    //==============================================================================================

    // inline fun check_if_project_exist(project: String): bool {
    //
    // }

    //==============================================================================================
    // Validation functions
    //==============================================================================================

    inline fun assert_admin(admin: address) {
        // TODO: Assert that the provided address is the admin address
        assert!(admin == @admin,SIGNER_NOT_ADMIN);
    }
}