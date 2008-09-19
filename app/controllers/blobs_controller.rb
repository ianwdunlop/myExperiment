# myExperiment: app/controllers/blobs_controller.rb
#
# Copyright (c) 2007 University of Manchester and the University of Southampton.
# See license.txt for details.

class BlobsController < ApplicationController
  before_filter :login_required, :except => [:index, :show, :download, :named_download, :search, :all]
  
  before_filter :find_blobs, :only => [:all]
  before_filter :find_blob_auth, :except => [:search, :index, :new, :create, :all]
  
  before_filter :initiliase_empty_objects_for_new_pages, :only => [:new, :create]
  
  before_filter :check_is_owner, :only => [:edit, :update]
  
  before_filter :invalidate_listing_cache, :only => [:show, :download, :named_download, :update, :comment, :comment_delete, :rate, :tag, :destroy]
  before_filter :invalidate_tags_cache, :only => [:create, :update, :delete, :tag]
  
  # GET /files;search
  def search

    @query = params[:query] == nil ? "" : params[:query]
    
    @blobs = SOLR_ENABLE ? Blob.find_by_solr(@query, :limit => 100).results : []
    
    respond_to do |format|
      format.html # search.rhtml
    end
  end
  
  # GET /files/1;download
  def download
    @download = Download.create(:contribution => @blob.contribution, :user => (logged_in? ? current_user : nil))
    
    send_data(@blob.content_blob.data, :filename => @blob.local_name, :type => @blob.content_type)
    
    #send_file("#{RAILS_ROOT}/#{controller_name}/#{@blob.contributor_type.downcase.pluralize}/#{@blob.contributor_id}/#{@blob.local_name}", :filename => @blob.local_name, :type => @blob.content_type)
  end

  # GET /files/:id/download/:name
  def named_download

    # check that we got the right filename for this workflow
    if params[:name] == @blob.local_name
      download
    else
      render :nothing => true, :status => "404 Not Found"
    end
  end

  # GET /files
  def index
    respond_to do |format|
      format.html # index.rhtml
    end
  end
  
  # GET /files/all
  def all
    respond_to do |format|
      format.html # all.rhtml
    end
  end
  
  # GET /files/1
  def show
    @viewing = Viewing.create(:contribution => @blob.contribution, :user => (logged_in? ? current_user : nil))
    
    @sharing_mode  = determine_sharing_mode(@blob)
    @updating_mode = determine_updating_mode(@blob)
    
    respond_to do |format|
      format.html # show.rhtml
    end
  end
  
  # GET /files/new
  def new
  end
  
  # GET /files/1;edit
  def edit
    
    @sharing_mode  = determine_sharing_mode(@blob)
    @updating_mode = determine_updating_mode(@blob)
  end
  
  # POST /blobs
  def create
    
    # don't create new blob if no file has been selected
    if params[:blob][:data].size == 0
      respond_to do |format|
        flash.now[:error] = "Please select a file to upload."
        format.html { render :action => "new" }
      end
    else
      data = params[:blob][:data].read
      params[:blob][:local_name] = params[:blob][:data].original_filename
      params[:blob][:content_type] = params[:blob][:data].content_type
      params[:blob].delete('data')

      params[:blob][:contributor_type], params[:blob][:contributor_id] = "User", current_user.id
   
      @blob = Blob.new(params[:blob])
      @blob.content_blob = ContentBlob.new(:data => data)

      respond_to do |format|
        if @blob.save
          if params[:blob][:tag_list]
            @blob.tags_user_id = current_user
            @blob.tag_list = convert_tags_to_gem_format params[:blob][:tag_list]
            @blob.update_tags
          end
          # update policy
          @blob.contribution.update_attributes(params[:contribution])
        
          update_policy(@blob, params)
        
          update_credits(@blob, params)
          update_attributions(@blob, params)
        
          flash[:notice] = 'File was successfully created.'
          format.html { redirect_to file_url(@blob) }
        else
          format.html { render :action => "new" }
        end
      end
    end
  end
  
  # PUT /files/1
  def update
    # hack for select contributor form
    if params[:contributor_pair]
      params[:contribution][:contributor_type], params[:contribution][:contributor_id] = params[:contributor_pair][:class_id].split("-")
      params.delete("contributor_pair")
    end
    
    # remove protected columns
    if params[:blob]
      [:contributor_id, :contributor_type, :content_type, :local_name, :created_at, :updated_at].each do |column_name|
        params[:blob].delete(column_name)
      end
    end
    
    # 'Data' (ie: the actual file) cannot be updated!
    params[:blob].delete('data') if params[:blob][:data]
    
    respond_to do |format|
      if @blob.update_attributes(params[:blob])
        @blob.refresh_tags(convert_tags_to_gem_format(params[:blob][:tag_list]), current_user) if params[:blob][:tag_list]
        update_policy(@blob, params)
        update_credits(@blob, params)
        update_attributions(@blob, params)
        
        flash[:notice] = 'File was successfully updated.'
        format.html { redirect_to file_url(@blob) }
      else
        format.html { render :action => "edit" }
      end
    end
  end
  
  # DELETE /files/1
  def destroy
    success = @blob.destroy

    respond_to do |format|
      if success
        flash[:notice] = "File has been deleted."
        format.html { redirect_to files_url }
      else
        flash[:error] = "Failed to delete File. Please contact your administrator."
        format.html { redirect_to file_url(@blob) }
      end
    end
  end
  
  # POST /files/1;comment
  def comment 
    text = params[:comment][:comment]
    
    if text and text.length > 0
      comment = Comment.create(:user => current_user, :comment => text)
      @blob.comments << comment
    end
    
    respond_to do |format|
      format.html { render :partial => "comments/comments", :locals => { :commentable => @blob } }
    end
  end
  
  # DELETE /files/1;comment_delete
  def comment_delete
    if params[:comment_id]
      comment = Comment.find(params[:comment_id].to_i)
      # security checks:
      if comment.user_id == current_user.id and comment.commentable_type.downcase == 'blob' and comment.commentable_id == @blob.id
        comment.destroy
      end
    end
    
    respond_to do |format|
      format.html { render :partial => "comments/comments", :locals => { :commentable => @blob } }
    end
  end
  
  # POST /files/1;rate
  def rate
    if @blob.contributor_type == 'User' and @blob.contributor_id == current_user.id
      error("You cannot rate your own file!", "")
    else
      Rating.delete_all(["rateable_type = ? AND rateable_id = ? AND user_id = ?", @blob.class.to_s, @blob.id, current_user.id])
      
      @blob.ratings << Rating.create(:user => current_user, :rating => params[:rating])
      
      respond_to do |format|
        format.html { 
          render :update do |page|
            page.replace_html "ratings_inner", :partial => "contributions/ratings_box_inner", :locals => { :contributable => @blob, :controller_name => controller.controller_name }
            page.replace_html "ratings_breakdown", :partial => "contributions/ratings_box_breakdown", :locals => { :contributable => @blob }
          end }
      end
    end
  end
  
  # POST /files/1;tag
  def tag
    files.tags_user_id = current_user # acts_as_taggable_redux
    @blob.tag_list = "#{@blob.tag_list}, #{convert_tags_to_gem_format params[:tag_list]}" if params[:tag_list]
    @blob.update_tags # hack to get around acts_as_versioned
    
    respond_to do |format|
      format.html { render :partial => "tags/tags_box_inner", :locals => { :taggable => @blob, :owner_id => @blob.contributor_id } }
    end
  end
  
  # POST /files/1;favourite
  def favourite
    @blob.bookmarks << Bookmark.create(:user => current_user) unless @blob.bookmarked_by_user?(current_user)
    
    respond_to do |format|
      flash[:notice] = "You have successfully added this item to your favourites."
      format.html { redirect_to file_url(@blob) }
    end
  end
  
  # DELETE /files/1;favourite_delete
  def favourite_delete
    @blob.bookmarks.each do |b|
      if b.user_id == current_user.id
        b.destroy
      end
    end
    
    respond_to do |format|
      flash[:notice] = "You have successfully removed this item from your favourites."
      redirect_url = params[:return_to] ? params[:return_to] : file_url(@blob)
      format.html { redirect_to redirect_url }
    end
  end
  
  protected
  
  def find_blobs
    found = Blob.find(:all, 
                       :order => "content_type ASC, local_name ASC, created_at DESC",
                       :page => { :size => 20, 
                       :current => params[:page] })
    
    found.each do |blob|
      blob.content_blob.data = nil unless blob.authorized?("download", (logged_in? ? current_user : nil))
    end
    
    @blobs = found
  end
  
  def find_blob_auth
    begin
      blob = Blob.find(params[:id])
      
      if blob.authorized?(action_name, (logged_in? ? current_user : nil))
        @blob = blob
        
        @blob_entry_url = url_for :only_path => false,
                            :host => base_host,
                            :id => @blob.id

        @named_download_url = url_for :action => 'named_download',
                                      :id => @blob.id, 
                                      :version => 1, # blobs aren't versioned (yet)
                                      :name => @blob.local_name

      else
        if logged_in? 
          error("File not found (id not authorized)", "is invalid (not authorized)")
        else
          find_blob_auth if login_required
        end
      end
      rescue ActiveRecord::RecordNotFound
      error("File not found", "is invalid")
    end
  end
  
  def initiliase_empty_objects_for_new_pages
    if ["new", "create"].include?(action_name)
      @blob = Blob.new
      @sharing_mode  = 0
      @updating_mode = 6
    end
  end
  
  def check_is_owner
    if @blob
      error("You are not authorised to manage this File", "") unless @blob.owner?(current_user)
    end
  end
  
  def invalidate_listing_cache
    if @blob
      expire_fragment(:controller => 'files_cache', :action => 'listing', :id => @blob.id)
    end
  end
  
  def invalidate_tags_cache
    expire_fragment(:controller => 'files', :action => 'all_tags')
    expire_fragment(:controller => 'sidebar_cache', :action => 'tags', :part => 'most_popular_tags')
  end
  
  private
  
  def error(notice, message, attr=:id)
    flash[:error] = notice
     (err = Blob.new.errors).add(attr, message)
    
    respond_to do |format|
      format.html { redirect_to files_url }
    end
  end
end
