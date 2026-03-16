# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
# db/seeds.rb

# 1. Clean the database 🗑️
puts "Cleaning database..."
Message.destroy_all
Chat.destroy_all
Job.destroy_all
User.destroy_all

# 2. Create users
puts "Creating users..."
User.create!(email: "test@test.com", password: "Wagon2026!")
User.create!(email: "ines@lewagon.com", password: "Wagon2026!")
User.create!(email: "gustavo@lewagon.com", password: "Wagon2026!")
User.create!(email: "rafaela@lewagon.com", password: "Wagon2026!")
User.create!(email: "clara@lewagon.com", password: "Wagon2026!")

# 3. Create the instances 🏗️
puts "Creating jobs..."
Job.create!([
  {
    job_title: "Junior Developer",
    job_description: "Entry-level software development role focusing on Ruby on Rails and JavaScript."
  },
  {
    job_title: "Product Manager",
    job_description: "Managing product roadmap, working with engineering and design teams."
  },
  {
    job_title: "Data Analyst",
    job_description: "Analysing data, building dashboards and reporting insights to stakeholders."
  },
  {
    job_title: "UX Designer",
    job_description: "Designing user interfaces and conducting user research."
  },
])

# 3. Display a message 🎉
puts "Finished! Created #{Job.count} jobs."
