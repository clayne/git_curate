require "spec_helper"

describe GitCurate::Runner do

  describe "#initialize" do
    it "returns a Runner initialized with the passed options" do
      runner0 = GitCurate::Runner.new(list: true)
      expect(runner0.instance_variable_get("@opts")[:list]).to eq(true)
      expect(runner0.instance_variable_get("@opts")[:merged_opt]).to eq(nil)

      runner1 = GitCurate::Runner.new(list: false, merged_opt: "--no-merged")
      expect(runner1.instance_variable_get("@opts")[:list]).to eq(false)
      expect(runner1.instance_variable_get("@opts")[:merged_opt]).to eq("--no-merged")
    end
  end

  describe "#run" do
    subject { runner.run(args) }
    let(:runner) { GitCurate::Runner.new(opts) }
    let(:opts) { { list: list, merged_opt: merged_opt } }
    let(:list) { true }
    let(:merged_opt) { nil }

    before(:each) do
      @branch_0 = GitCurate::Branch.new("a-master", merged: false, upstream_info: "Up to date")
      allow(@branch_0).to receive(:hash).and_return("80abe0c")
      allow(@branch_0).to receive(:last_commit_date).and_return("2019-03-01")
      allow(@branch_0).to receive(:last_author).and_return("Jane Smithers")
      allow(@branch_0).to receive(:last_subject).and_return("Do some things to the code")

      @branch_1 = GitCurate::Branch.new("b/other-branch", merged: false, upstream_info: "Behind 15")
      allow(@branch_1).to receive(:hash).and_return("10abf0c")
      allow(@branch_1).to receive(:last_commit_date).and_return("2019-05-02")
      allow(@branch_1).to receive(:last_author).and_return("John Smith")
      allow(@branch_1).to receive(:last_subject).and_return("Implement that cool feature")

      @branch_2 = GitCurate::Branch.new("* c-another-one", merged: true, upstream_info: "No upstream")
      allow(@branch_2).to receive(:hash).and_return("90abfbc")
      allow(@branch_2).to receive(:last_commit_date).and_return("2017-11-24")
      allow(@branch_2).to receive(:last_author).and_return("John Smith")
      allow(@branch_2).to receive(:last_subject).and_return("Fix that bug")

      @branch_3 = GitCurate::Branch.new("d-fourth", merged: false, upstream_info: "No upstream")
      allow(@branch_3).to receive(:hash).and_return("90abfbc")
      allow(@branch_3).to receive(:last_commit_date).and_return("2017-11-24")
      allow(@branch_3).to receive(:last_author).and_return("John Smith")
      allow(@branch_3).to receive(:last_subject).and_return("Fix that bug")

      @branch_4 = GitCurate::Branch.new("e-fifth", merged: true, upstream_info: "Ahead 1, behind 2")
      allow(@branch_4).to receive(:hash).and_return("134698e")
      allow(@branch_4).to receive(:last_commit_date).and_return("2010-08-08")
      allow(@branch_4).to receive(:last_author).and_return("Alicia Keys")
      allow(@branch_4).to receive(:last_subject).and_return("More things")
    end

    before(:each) do
      (@captured_output ||= []).clear
      allow(GitCurate::Branch).to receive(:local).and_return(branches)
      allow(TTY::Screen).to receive(:width).and_return(200)
      allow($stdout).to receive(:puts) { |output| @captured_output << output.to_s }
    end

    context "when there are non-checked-out branches" do
      let(:branches) { [@branch_0, @branch_1, @branch_2, @branch_3, @branch_4] }

      context "when passed arguments" do
        let(:args) { ['hi'] }
        before(:each) { allow($stderr).to receive(:puts).and_return(nil) }

        it "returns a code of 1, indicating failure" do
          is_expected.to eq(1)
        end

        it "prints an error message to STDERR" do
          expect(STDERR).to receive(:puts).with("This script does not accept any arguments.")
          subject
        end
      end

      context "when not passed any arguments" do
        let(:args) { [] }
        before(:each) { allow(GitCurate::Branch).to receive(:delete_multi) }

        context "when Runner was initialized with `merged_opt: '--no-merged'`" do
          let(:merged_opt) { "--no-merged" }

          it "lists only non-merged branches" do
            expect(GitCurate::Branch).to receive(:local).with("--no-merged")
            subject
          end
        end

        context "when Runner was initialized with `merged_opt: '--merged'`" do
          let(:merged_opt) { "--merged" }

          it "lists only merged branches" do
            expect(GitCurate::Branch).to receive(:local).with("--merged")
            subject
          end
        end

        context "when Runner was initialized with `list: true`" do
          let(:list) { true }

          it "outputs a list of branch information" do
            # Doing it like this to stop text editor automatically deleting trailing whitespace
            expected_output = [
  "---------------- ------------ ------- ------------- --------------------------- ---------- -----------------",
  "Branch           Last commit:                                                   Merged     Status vs        ",
  "                 Date         Hash    Author        Subject                     into HEAD? upstream         ",
  "---------------- ------------ ------- ------------- --------------------------- ---------- -----------------",
  "  a-master       2019-03-01   80abe0c Jane Smithers Do some things to the code  Not merged Up to date       ",
  "  b/other-branch 2019-05-02   10abf0c John Smith    Implement that cool feature Not merged Behind 15        ",
  "* c-another-one  2017-11-24   90abfbc John Smith    Fix that bug                Merged     No upstream      ",
  "  d-fourth       2017-11-24   90abfbc John Smith    Fix that bug                Not merged No upstream      ",
  "  e-fifth        2010-08-08   134698e Alicia Keys   More things                 Merged     Ahead 1, behind 2",
  "---------------- ------------ ------- ------------- --------------------------- ---------- -----------------",
            ].join($/)

            subject

            expect(@captured_output.last).to eq(expected_output)
          end

          it "returns a code of 0, indicating success" do
            is_expected.to eq(0)
          end
        end

        context "when Runner was initialized with `list: false`" do
          let(:list) { false }
          let(:user_responses) { ["d", "", "K", "D"] }
          before(:each) { allow(HighLine).to receive(:ask).and_return(*user_responses) }

          it "prompts the user once for each branch other than the current one, continuing if the user enters a d/D/k/K/<blank>" do
            expect(HighLine).to receive(:ask).exactly(4).times
            subject
          end

          it "deletes each branch for which the user enters 'd' or 'D'" do
            expect(GitCurate::Branch).to receive(:delete_multi).with(@branch_0, @branch_4)
            subject
          end

          it "returns a status code of 0" do
            is_expected.to eq(0)
          end

          context "when the user enters 'a'" do
            let(:user_responses) { ["d", "D", "a"] }

            it "exits early" do
              expect(HighLine).to receive(:ask).exactly(3).times
              subject
            end

            it "does not delete any branches" do
              expect(GitCurate::Branch).not_to receive(:delete_multi)
              subject
            end

            it "returns a status code of 0" do
              is_expected.to eq(0)
            end
          end

          context "when the user enters 'e'" do
            let(:user_responses) { ["d", "", "e"] }

            it "exits early" do
              expect(HighLine).to receive(:ask).exactly(3).times
              subject
            end

            it "deletes the branches that the user has selected for deletion using 'd'/'D'" do
              expect(GitCurate::Branch).to receive(:delete_multi).with(@branch_0)
              subject
            end

            it "returns a status code of 0" do
              is_expected.to eq(0)
            end
          end

          context "when the user enters 'help'" do
            let(:user_responses) { ["k", "help", "k", "k"] }

            it "outputs help text" do
              # Doing it like this to stop text editor automatically deleting trailing whitespace
              expected_help_text = [
                "           d : delete branch                              ",
                " k / <enter> : keep branch                                ",
                "           e : end session, deleting all selected branches",
                "           a : abort session, keeping all branches        ",
              ].join($/)

              subject

              expect(@captured_output).to include(expected_help_text)
            end
          end
        end
      end
    end

    context "when there are only checked-out branches" do
      let(:branches) { [@branch_2] }
      let(:args) { [] }

      context "when Runner was initialized with `list: false`" do
        let(:list) { false }

        it "does not prompt the user" do
          expect(HighLine).not_to receive(:ask)
          subject
        end

        it "returns a status code of 0" do
          is_expected.to eq(0)
        end

        it "tells the user that there are no local branches that can be deleted" do
          subject
          expect(@captured_output).to eq(["There are no local branches that can be deleted."])
        end
      end
    end
  end

end
