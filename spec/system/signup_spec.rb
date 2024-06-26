# frozen_string_literal: true

describe "Signup", type: :system do
  let(:login_modal) { PageObjects::Modals::Login.new }
  let(:signup_modal) { PageObjects::Modals::Signup.new }

  context "when anyone can create an account" do
    it "can signup and activate account" do
      Jobs.run_immediately!

      signup_modal.open
      signup_modal.fill_email("johndoe@example.com")
      signup_modal.fill_username("john")
      signup_modal.fill_password("supersecurepassword")
      expect(signup_modal).to have_valid_fields
      signup_modal.click_create_account

      wait_for(timeout: 5) { ActionMailer::Base.deliveries.count != 0 }

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to contain_exactly("johndoe@example.com")
      activation_link = mail.body.to_s[%r{/u/activate-account/\S+}]

      visit "/"
      visit activation_link
      find("#activate-account-button").click

      visit "/"
      expect(page).to have_css(".header-dropdown-toggle.current-user")
    end

    context "with invite code" do
      before { SiteSetting.invite_code = "cupcake" }

      it "can signup with valid code" do
        signup_modal.open
        signup_modal.fill_email("johndoe@example.com")
        signup_modal.fill_username("john")
        signup_modal.fill_password("supersecurepassword")
        signup_modal.fill_code("cupcake")
        expect(signup_modal).to have_valid_fields

        signup_modal.click_create_account
        expect(page).to have_css(".account-created")
      end

      it "cannot signup with invalid code" do
        signup_modal.open
        signup_modal.fill_email("johndoe@example.com")
        signup_modal.fill_username("john")
        signup_modal.fill_password("supersecurepassword")
        signup_modal.fill_code("pudding")
        expect(signup_modal).to have_valid_fields

        signup_modal.click_create_account
        expect(signup_modal).to have_content(I18n.t("login.wrong_invite_code"))
        expect(signup_modal).to have_no_css(".account-created")
      end
    end

    context "when user requires approval" do
      before do
        SiteSetting.must_approve_users = true
        SiteSetting.auto_approve_email_domains = "awesomeemail.com"
      end

      it "can signup but cannot login until approval" do
        signup_modal.open
        signup_modal.fill_email("johndoe@example.com")
        signup_modal.fill_username("john")
        signup_modal.fill_password("supersecurepassword")
        expect(signup_modal).to have_valid_fields
        signup_modal.click_create_account

        visit "/"
        login_modal.open
        login_modal.fill_username("john")
        login_modal.fill_password("supersecurepassword")
        login_modal.click_login
        expect(login_modal).to have_content(I18n.t("login.not_approved"))

        wait_for(timeout: 5) { User.find_by(username: "john") != nil }
        user = User.find_by(username: "john")
        user.update!(approved: true)
        EmailToken.confirm(Fabricate(:email_token, user: user).token)

        login_modal.click_login
        expect(page).to have_css(".header-dropdown-toggle.current-user")
      end

      it "can login directly when using an auto approved email" do
        signup_modal.open
        signup_modal.fill_email("johndoe@awesomeemail.com")
        signup_modal.fill_username("john")
        signup_modal.fill_password("supersecurepassword")
        expect(signup_modal).to have_valid_fields
        signup_modal.click_create_account

        wait_for(timeout: 5) { User.find_by(username: "john") != nil }
        user = User.find_by(username: "john")
        EmailToken.confirm(Fabricate(:email_token, user: user).token)

        login_modal.open
        login_modal.fill_username("john")
        login_modal.fill_password("supersecurepassword")
        login_modal.click_login
        expect(page).to have_css(".header-dropdown-toggle.current-user")
      end
    end
  end

  context "when the email domain is blocked" do
    before { SiteSetting.blocked_email_domains = "example.com" }

    it "cannot signup" do
      signup_modal.open
      signup_modal.fill_email("johndoe@example.com")
      signup_modal.fill_username("john")
      signup_modal.fill_password("supersecurepassword")
      expect(signup_modal).to have_valid_username
      expect(signup_modal).to have_valid_password
      expect(signup_modal).to have_content(I18n.t("user.email.not_allowed"))
    end
  end

  context "when site is invite only" do
    before { SiteSetting.invite_only = true }

    it "cannot open the signup modal" do
      signup_modal.open
      expect(signup_modal).to be_closed
      expect(page).to have_no_css(".sign-up-button")

      login_modal.open_from_header
      expect(login_modal).to have_no_css("#new-account-link")
    end

    it "can signup with invite link" do
      invite = Fabricate(:invite, email: "johndoe@example.com")
      visit "/invites/#{invite.invite_key}?t=#{invite.email_token}"

      find("#new-account-password").fill_in(with: "supersecurepassword")
      find(".username-input").has_css?("#username-validation.good")
      find(".create-account__password-tip-validation").has_css?("#password-validation.good")
      find(".invitation-cta__accept").click

      expect(page).to have_css(".header-dropdown-toggle.current-user")
    end
  end
end
