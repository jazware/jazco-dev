# Use the official Jekyll image as base
FROM jekyll/jekyll:4.2.2

# Set the working directory
WORKDIR /srv/jekyll

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Install dependencies
RUN bundle install

# Copy the rest of the site
COPY . .

# Expose the default Jekyll server port
EXPOSE 4000

# Run Jekyll server with live reloading enabled
CMD ["jekyll", "serve", "--livereload", "--force_polling", "--host", "0.0.0.0"]
