All features must have tests and bug fixes must have regression tests.

DO THE FOLLOWING:

- Implement the feature or bug fix as normal, but do not commit it. Once you've completed the work and manually tested it, use `git stash`, write the test and validate that it fails as expected, then do `git stash pop`.
- If that's not possible (e.g. you are testing code that is already committed), try to comment out or disable the applicable code in the least obtrusive way possible, and then verify that the test fails as expected.