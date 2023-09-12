module admin::daptorator{

    //==============================================================================================
    // Dependencies
    //==============================================================================================

    use std::object;
    use std::signer;
    use aptos_framework::option;
    use aptos_token_objects::token;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account::{Self, SignerCapability};
    use std::string::{Self, String};
    use aptos_token_objects::collection;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_std::simple_map;
    use aptos_std::simple_map::SimpleMap;
    use std::bcs;

    #[test_only]
    use aptos_token_objects::royalty;

    //==============================================================================================
    // Errors
    //==============================================================================================

    const SIGNER_NOT_ADMIN: u64 = 0;
    const METADATA_DUPLICATED: u64 = 1;
    const OTHER_ERRORS: u64 = 2;

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


    //==============================================================================================
    // Module Structs
    //==============================================================================================

    struct ReviewToken has key {
        // Used for editing the token data
        mutator_ref: token::MutatorRef,
        // Used for burning the token
        burn_ref: token::BurnRef
    }

    /*
        Information to be used in the module
    */
    struct State has key {
        // signer cap of the module's resource account
        signer_cap: SignerCapability,
        // SimpleMap<Metadata, review_token_address>
        metadatas: SimpleMap<vector<u8>, address>,
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
        metadata: String,
        //output log for frontend
        category: String,
        domain_address: String,
        site_url: String,
        site_type: String,
        site_tag: String,
        site_safety: String,
        // timestamp
        timestamp: u64
    }

    struct ReviewDeleted has store, drop {
        // review_hash
        metadata: String,
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
        collection::create_unlimited_collection(
            &resource_signer,
            string::utf8(COLLECTION_DESCRIPTION),
            string::utf8(COLLECTION_NAME),
            option::none(),
            string::utf8(COLLECTION_URI)
        );

        // Create the State global resource and move it to the admin account
        let state = State{
            signer_cap: resource_cap,
            metadatas: simple_map::new(),
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
        metadata: String,
        category: String,
        domain_address: String,
        site_url: String,
        site_type: String,
        site_tag: String,
        site_safety: String
    ) acquires State {
        let review_hash = bcs::to_bytes(&metadata);
        assert_metadata_not_duplicated(review_hash);
        let state = borrow_global_mut<State>(@admin);
        let res_signer = account::create_signer_with_capability(&state.signer_cap);

        // Create a new named token:
        let token_const_ref = token::create_named_token(
            &res_signer,
            string::utf8(COLLECTION_NAME),
            string::utf8(TOKEN_DESCRIPTION),
            metadata,
            option::none(),
            metadata
        );

        let obj_signer = object::generate_signer(&token_const_ref);

        // Transfer the token to the reviewer account
        object::transfer_raw(&res_signer, object::address_from_constructor_ref(&token_const_ref), signer::address_of(reviewer));

        // Create the ReviewToken object and move it to the new token object signer
        let new_review_token = ReviewToken{
            mutator_ref: token::generate_mutator_ref(&token_const_ref),
            burn_ref: token::generate_burn_ref(&token_const_ref),
        };

        move_to(&obj_signer, new_review_token);
        simple_map::add(&mut state.metadatas, review_hash, object::address_from_constructor_ref(&token_const_ref));

        // Emit a new ReviewSubmittedEvent
        event::emit_event<ReviewSubmitted>(
            &mut state.review_submitted_events,
            ReviewSubmitted{
                reviewer: signer::address_of(reviewer),
                review_token_address: object::address_from_constructor_ref(&token_const_ref),
                metadata,
                category,
                domain_address,
                site_url,
                site_type,
                site_tag,
                site_safety,
                timestamp: timestamp::now_seconds()
            });
    }

    //delegate mint - will not cost users to mint reviews
    public entry fun submit_review_admin_sign(
        admin: &signer,
        reviewer: address,
        metadata: String,
        category: String,
        domain_address: String,
        site_url: String,
        site_type: String,
        site_tag: String,
        site_safety: String
    ) acquires State {
        let review_hash = bcs::to_bytes(&metadata);
        assert_metadata_not_duplicated(review_hash);
        let state = borrow_global_mut<State>(signer::address_of(admin));
        let res_signer = account::create_signer_with_capability(&state.signer_cap);

        // Create a new named token:
        let token_const_ref = token::create_named_token(
            &res_signer,
            string::utf8(COLLECTION_NAME),
            string::utf8(TOKEN_DESCRIPTION),
            metadata,
            option::none(),
            metadata
        );

        let obj_signer = object::generate_signer(&token_const_ref);

        // Transfer the token to the reviewer account
        object::transfer_raw(&res_signer, object::address_from_constructor_ref(&token_const_ref), reviewer);

        // Create the ReviewToken object and move it to the new token object signer
        let new_review_token = ReviewToken{
            mutator_ref: token::generate_mutator_ref(&token_const_ref),
            burn_ref: token::generate_burn_ref(&token_const_ref),
        };

        move_to(&obj_signer, new_review_token);
        simple_map::add(&mut state.metadatas, review_hash, object::address_from_constructor_ref(&token_const_ref));

        // Emit a new ReviewSubmittedEvent
        event::emit_event<ReviewSubmitted>(
            &mut state.review_submitted_events,
            ReviewSubmitted{
                reviewer,
                review_token_address: object::address_from_constructor_ref(&token_const_ref),
                metadata,
                category,
                domain_address,
                site_url,
                site_type,
                site_tag,
                site_safety,
                timestamp: timestamp::now_seconds()
            });
    }

    public entry fun delete_review(
        admin: &signer,
        metadata: String
    ) acquires State, ReviewToken {
        let review_hash = bcs::to_bytes(&metadata);
        assert_admin(signer::address_of(admin));
        let state = borrow_global_mut<State>(@admin);
        let review_token_address = *simple_map::borrow(&state.metadatas, &review_hash);
        let review_token_object = object::address_to_object<ReviewToken>(review_token_address);
        let reviewer = object::owner(review_token_object);
        let review_token = move_from<ReviewToken>(review_token_address);
        let ReviewToken{mutator_ref: _, burn_ref} = review_token;

        // Burn the the token
        token::burn(burn_ref);

        // Note that since named objects have deterministic addresses, they cannot be deleted.
        // This is to prevent a malicious user from creating an object with the same seed as a named object and deleting it.

        // Emit a new ReviewDeletedEvent
        simple_map::remove(&mut state.metadatas, &review_hash);
        event::emit_event<ReviewDeleted>(
            &mut state.review_deleted_events,
            ReviewDeleted{
                metadata,
                reviewer,
                timestamp: timestamp::now_seconds()
            });
    }

    //==============================================================================================
    // Helper functions
    //==============================================================================================

    #[view]
    public fun check_if_metadata_exists(metadata: String): bool acquires State {
        let state = borrow_global<State>(@admin);
        simple_map::contains_key(&state.metadatas, &bcs::to_bytes(&metadata))
    }

    #[view]
    public fun total_reviews(): u64 acquires State {
        let state = borrow_global<State>(@admin);
        simple_map::length(&state.metadatas)
    }

    //==============================================================================================
    // Validation functions
    //==============================================================================================

    inline fun assert_admin(admin: address) {
        assert!(admin == @admin,SIGNER_NOT_ADMIN);
    }

    inline fun assert_metadata_not_duplicated(review_hash: vector<u8>) {
        let state = borrow_global<State>(@admin);
        assert!(!simple_map::contains_key(&state.metadatas, &review_hash), METADATA_DUPLICATED);
    }

    //==============================================================================================
    // Test functions
    //==============================================================================================

    #[test(admin = @admin)]
    fun test_init_module_success(
        admin: &signer
    ) acquires State {
        let admin_address = signer::address_of(admin);
        account::create_account_for_test(admin_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(admin);

        let expected_resource_account_address = account::create_resource_address(&admin_address, SEED);
        assert!(account::exists_at(expected_resource_account_address), 0);

        let state = borrow_global<State>(admin_address);
        assert!(
            account::get_signer_capability_address(&state.signer_cap) == expected_resource_account_address,
            0
        );
        assert!(
            simple_map::length(&state.metadatas) == 0,
            2
        );

        assert!(
            coin::is_account_registered<AptosCoin>(expected_resource_account_address),
            2
        );

        let expected_collection_address = collection::create_collection_address(
            &expected_resource_account_address,
            &string::utf8(b"Review collection name")
        );
        let collection_object = object::address_to_object<collection::Collection>(expected_collection_address);
        assert!(
            collection::creator<collection::Collection>(collection_object) == expected_resource_account_address,
            2
        );
        assert!(
            collection::name<collection::Collection>(collection_object) == string::utf8(b"Review collection name"),
            2
        );
        assert!(
            collection::description<collection::Collection>(collection_object) == string::utf8(b"Review collection description"),
            2
        );
        assert!(
            collection::uri<collection::Collection>(collection_object) == string::utf8(b"Review collection uri"),
            2
        );

        assert!(event::counter(&state.review_submitted_events) == 0, 2);
        assert!(event::counter(&state.review_deleted_events) == 0, 2);
    }

    #[test(admin = @admin, reviewer = @0xA)]
    fun test_reviewer_success(
        admin: &signer,
        reviewer: &signer
    ) acquires State {
        let admin_address = signer::address_of(admin);
        let reviwer_address = signer::address_of(reviewer);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(reviwer_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(admin);

        let metadata = string::utf8(b"QmSYRXWGGqVDAHKTwfnYQDR74d4bfwXxudFosbGA695AWS");
        let category = string::utf8(b"Website");
        let domain_address = string::utf8(b"mystic.com");
        let site_url = string::utf8(b"todo.mystic.com");
        let site_type = string::utf8(b"Productivity app");
        let site_tag = string::utf8(b"Web3 Project");
        let site_safety = string::utf8(b"Genuine");

        submit_review(
            reviewer,
            metadata,
            category,
            domain_address,
            site_url,
            site_type,
            site_tag,
            site_safety
        );


        let resource_account_address = account::create_resource_address(&@admin, SEED);

        let expected_review_token_address = token::create_token_address(
            &resource_account_address,
            &string::utf8(b"Review collection name"),
            &metadata
        );
        let review_token_object = object::address_to_object<token::Token>(expected_review_token_address);
        assert!(
            object::is_owner(review_token_object, reviwer_address) == true,
            2
        );
        assert!(
            token::creator(review_token_object) == resource_account_address,
            2
        );
        assert!(
            token::name(review_token_object) == metadata,
            2
        );
        assert!(
            token::description(review_token_object) == string::utf8(b"Review token description"),
            2
        );
        assert!(
            token::uri(review_token_object) == metadata,
            2
        );
        assert!(
            option::is_none<royalty::Royalty>(&token::royalty(review_token_object)),
            2
        );

        let state = borrow_global<State>(admin_address);
        assert!(
            simple_map::length(&state.metadatas) == 1,
            2
        );

        assert!(event::counter(&state.review_submitted_events) == 1, 2);
        assert!(event::counter(&state.review_deleted_events) == 0, 2);
    }

    #[test(admin = @admin, reviewer = @0xA)]
    #[expected_failure(abort_code = METADATA_DUPLICATED)]
    fun test_reviewer_failure_duplicated_review(
        admin: &signer,
        reviewer: &signer
    ) acquires State {
        let admin_address = signer::address_of(admin);
        let reviwer_address = signer::address_of(reviewer);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(reviwer_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(admin);

        let metadata = string::utf8(b"QmSYRXWGGqVDAHKTwfnYQDR74d4bfwXxudFosbGA695AWS");
        let category = string::utf8(b"Website");
        let domain_address = string::utf8(b"mystic.com");
        let site_url = string::utf8(b"todo.mystic.com");
        let site_type = string::utf8(b"Productivity app");
        let site_tag = string::utf8(b"Web3 Project");
        let site_safety = string::utf8(b"Genuine");

        submit_review(
            reviewer,
            metadata,
            category,
            domain_address,
            site_url,
            site_type,
            site_tag,
            site_safety
        );

        submit_review(
            reviewer,
            metadata,
            category,
            domain_address,
            site_url,
            site_type,
            site_tag,
            site_safety
        );
    }

    #[test(admin = @admin, reviewer = @0xA)]
    fun test_reviewer_admin_signer_success(
        admin: &signer,
        reviewer: &signer
    ) acquires State {
        let admin_address = signer::address_of(admin);
        let reviewer_address = signer::address_of(reviewer);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(reviewer_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(admin);

        let metadata = string::utf8(b"QmSYRXWGGqVDAHKTwfnYQDR74d4bfwXxudFosbGA695AWS");
        let category = string::utf8(b"Website");
        let domain_address = string::utf8(b"mystic.com");
        let site_url = string::utf8(b"todo.mystic.com");
        let site_type = string::utf8(b"Productivity app");
        let site_tag = string::utf8(b"Web3 Project");
        let site_safety = string::utf8(b"Genuine");

        submit_review(
            reviewer,
            metadata,
            category,
            domain_address,
            site_url,
            site_type,
            site_tag,
            site_safety
        );


        let resource_account_address = account::create_resource_address(&@admin, SEED);

        let expected_review_token_address = token::create_token_address(
            &resource_account_address,
            &string::utf8(b"Review collection name"),
            &metadata
        );
        let review_token_object = object::address_to_object<token::Token>(expected_review_token_address);
        assert!(
            object::is_owner(review_token_object, reviewer_address) == true,
            2
        );
        assert!(
            token::creator(review_token_object) == resource_account_address,
            2
        );
        assert!(
            token::name(review_token_object) == metadata,
            2
        );
        assert!(
            token::description(review_token_object) == string::utf8(b"Review token description"),
            2
        );
        assert!(
            token::uri(review_token_object) == metadata,
            2
        );
        assert!(
            option::is_none<royalty::Royalty>(&token::royalty(review_token_object)),
            2
        );

        let state = borrow_global<State>(admin_address);
        assert!(
            simple_map::length(&state.metadatas) == 1,
            2
        );

        assert!(event::counter(&state.review_submitted_events) == 1, 2);
        assert!(event::counter(&state.review_deleted_events) == 0, 2);
    }

    #[test(admin = @admin, reviewer = @0xA)]
    fun test_delete_review_success(
        admin: &signer,
        reviewer: &signer
    ) acquires State, ReviewToken {
        let admin_address = signer::address_of(admin);
        let reviwer_address = signer::address_of(reviewer);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(reviwer_address);

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(admin);

        let metadata = string::utf8(b"QmSYRXWGGqVDAHKTwfnYQDR74d4bfwXxudFosbGA695AWS");
        let category = string::utf8(b"Website");
        let domain_address = string::utf8(b"mystic.com");
        let site_url = string::utf8(b"todo.mystic.com");
        let site_type = string::utf8(b"Productivity app");
        let site_tag = string::utf8(b"Web3 Project");
        let site_safety = string::utf8(b"Genuine");

        submit_review(
            reviewer,
            metadata,
            category,
            domain_address,
            site_url,
            site_type,
            site_tag,
            site_safety
        );

        let resource_account_address = account::create_resource_address(&@admin, SEED);

        let expected_review_token_address = token::create_token_address(
            &resource_account_address,
            &string::utf8(b"Review collection name"),
            &metadata
        );
        delete_review(admin, metadata);

        assert!(!exists<ReviewToken>(expected_review_token_address), 0);

        let state = borrow_global<State>(admin_address);
        assert!(simple_map::length(&state.metadatas) == 0, 2);
        assert!(event::counter(&state.review_submitted_events) == 1, 2);
        assert!(event::counter(&state.review_deleted_events) == 1, 2);
    }
}