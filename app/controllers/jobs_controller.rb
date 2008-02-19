# myExperiment: app/controllers/jobs_controller.rb
#
# Copyright (c) 2008 University of Manchester and the University of Southampton.
# See license.txt for details.

class JobsController < ApplicationController
  
  before_filter :login_required
  
  before_filter :find_experiment_auth
  
  before_filter :find_jobs, :only => [:index]
  before_filter :find_job_auth, :except => [:index, :new, :create]
  
  def index
    respond_to do |format|
      format.html # index.rhtml
    end
  end

  def show
    respond_to do |format|
      format.html # show.rhtml
    end
  end

  def new
    @job = Job.new
    @job.experiment = @experiment
    
    # Set defaults
    @job.title = "Job_#{Time.now.strftime('%Y%m%d-%H%M')}_#{current_user.name}"
    @job.runnable_type = "Workflow"
    @job.runner_type = "TavernaEnactor"
    
    respond_to do |format|
      format.html # new.rhtml
    end
  end

  def create
    success = true
    
    # Hard code certain values, for now.
    params[:job][:runnable_type] = 'Workflow'
    params[:job][:runner_type] = 'TavernaEnactor'
    
    @job = Job.new(params[:job])
    @job.experiment = @experiment
    @job.user = current_user
    
    # Check runnable is a valid one
    # (for now we can assume it's a Workflow)
    runnable = Workflow.find(:first, :conditions => ["id = ?", params[:job][:runnable_id]])
    if !runnable or !runnable.authorized?('download', current_user)
      success = false
      @job.errors.add(:runnable_id, "not valid or not authorized")
    else
      # Look for the specific version of that Workflow
      unless runnable.find_version(params[:job][:runnable_version])
        success = false
        @job.errors.add(:runnable_version, "not valid")
      end
    end
    
    # Check runner is a valid one
    # (for now we can assume it's a TavernaEnactor)
    runner = TavernaEnactor.find(:first, :conditions => ["id = ?", params[:job][:runner_id]])
    if !runner or !runner.authorized?('run', current_user)
      success = false
      @job.errors.add(:runner_id, "not valid or not authorized")
    end
    
    respond_to do |format|
      if success and @job.save
        flash[:notice] = "Job successfully created."
        format.html { redirect_to job_url(@experiment, @job) }
      else
        format.html { render :action => "new" }
      end
    end
  end

  def edit
    respond_to do |format|
      format.html # edit.rhtml
    end
  end

  def update
    respond_to do |format|
      if @job.update_attributes(params[:job])
        flash[:notice] = "Job was successfully updated."
        format.html { redirect_to job_url(@experiment, @job) }
      else
        format.html { render :action => "edit" }
      end
    end
  end

  def destroy
    respond_to do |format|
      if @job.destroy
        flash[:notice] = "Job \"#{@job.title}\" has been deleted"
        format.html { redirect_to jobs_url(@experiment) }
      else
        flash[:error] = "Failed to delete Job"
        format.html { redirect_to job_url(@experiment, @job) }
      end
    end
  end
  
  def save_inputs
    
      
    respond_to do |format|
      format.html { render :action => "show" }
    end
  end
  
protected

  def find_experiment_auth
    experiment = Experiment.find(:first, :conditions => ["id = ?", params[:experiment_id]])
    
    if experiment and experiment.authorized?(action_name, current_user)
      @experiment = experiment
    else
      error("The Experiment that this Job belongs to could not be found or the action is not authorized", "is invalid (not authorized)")
    end
  end
  
  def find_jobs
    @jobs = Job.find(:all, :conditions => ["experiment_id = ?", params[:experiment_id]])
  end

  def find_job_auth
    job = Job.find(:first, :conditions => ["id = ?", params[:id]])
      
    if job and job.authorized?(action_name, current_user)
      @job = job
    else
      error("Job not found or action not authorized", "is invalid (not authorized)")
    end
  end
  
private

  def error(notice, message, attr=:id)
    flash[:error] = notice
    (err = Job.new.errors).add(attr, message)
    
    respond_to do |format|
      format.html { redirect_to jobs_url(params[:experiment_id]) }
      format.xml { render :xml => err.to_xml }
    end
  end
end
