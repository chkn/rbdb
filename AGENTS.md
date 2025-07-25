# Workflow

All features must have tests and bug fixes must have regression tests.

DO THE FOLLOWING:

1. Implement the feature or bug fix as normal, but do not commit it.
2. Once you've completed the work and manually tested it, run `git stash`.
3. Now write the test and validate that it fails as expected (because the fix is stashed).
4. Run `git stash pop` and validate that the test now passes.

If the above is not possible (e.g. you are testing code that is already committed), try to comment out or disable the applicable code in the least obtrusive way possible, and then verify that the test fails as expected.