// ==============================================================================
// SmartShelf V2 - Product Catalog & Categories Management
// ==============================================================================

import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext';
import { supabase } from '../lib/supabase';
import type { Product, Category, UnitType } from '../types/database';
import {
  Tag,
  Plus,
  Search,
  Filter,
  Package,
  Scale,
  Barcode,
  CheckCircle2,
  XCircle,
  AlertCircle,
  FolderPlus,
} from 'lucide-react';

export const ProductsView: React.FC = () => {
  const { activeOrg, isOrgAdmin } = useAuth();
  const [products, setProducts] = useState<Product[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string>('ALL');

  // Modals
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showCategoryModal, setShowCategoryModal] = useState(false);

  // New Product Form State
  const [newProductName, setNewProductName] = useState('');
  const [newProductCategoryId, setNewProductCategoryId] = useState<string>('');
  const [newProductBarcode, setNewProductBarcode] = useState('');
  const [newProductSku, setNewProductSku] = useState('');
  const [newProductUnitType, setNewProductUnitType] = useState<UnitType>('PACKAGED');
  const [newProductDescription, setNewProductDescription] = useState('');

  // New Category Form State
  const [newCategoryName, setNewCategoryName] = useState('');
  const [newCategoryDesc, setNewCategoryDesc] = useState('');

  const [formSubmitting, setFormSubmitting] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [formSuccess, setFormSuccess] = useState<string | null>(null);

  const fetchCatalog = useCallback(async () => {
    if (!activeOrg) {
      setLoading(false);
      return;
    }
    setLoading(true);

    try {
      // 1. Fetch categories
      const { data: catData, error: catErr } = await supabase
        .from('categories')
        .select('*')
        .eq('organization_id', activeOrg.id)
        .order('name');

      if (catErr) console.error('Error fetching categories:', catErr);
      setCategories((catData as Category[]) || []);

      // 2. Fetch products
      const { data: prodData, error: prodErr } = await supabase
        .from('products')
        .select('*, category:categories(*)')
        .eq('organization_id', activeOrg.id)
        .order('name');

      if (prodErr) console.error('Error fetching products:', prodErr);
      setProducts((prodData as Product[]) || []);
    } catch (err) {
      console.error('Failed to load catalog:', err);
    } finally {
      setLoading(false);
    }
  }, [activeOrg]);

  useEffect(() => {
    fetchCatalog();
  }, [fetchCatalog]);

  const handleCreateProduct = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeOrg) return;
    setFormError(null);
    setFormSuccess(null);
    setFormSubmitting(true);

    try {
      const { error } = await supabase.rpc('create_product', {
        p_organization_id: activeOrg.id,
        p_category_id: newProductCategoryId ? newProductCategoryId : null,
        p_name: newProductName.trim(),
        p_barcode: newProductBarcode.trim() ? newProductBarcode.trim() : null,
        p_sku: newProductSku.trim() ? newProductSku.trim() : null,
        p_unit_type: newProductUnitType,
        p_description: newProductDescription.trim() ? newProductDescription.trim() : null,
      });

      if (error) {
        setFormError(error.message);
      } else {
        setFormSuccess(`Product "${newProductName}" enrolled in catalog successfully.`);
        setNewProductName('');
        setNewProductBarcode('');
        setNewProductSku('');
        setNewProductDescription('');
        await fetchCatalog();
        setTimeout(() => setShowCreateModal(false), 800);
      }
    } catch (err: unknown) {
      setFormError(err instanceof Error ? err.message : 'Failed to create product');
    } finally {
      setFormSubmitting(false);
    }
  };

  const handleCreateCategory = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeOrg) return;
    setFormError(null);
    setFormSubmitting(true);

    try {
      const { data, error } = await supabase.rpc('create_category', {
        p_organization_id: activeOrg.id,
        p_name: newCategoryName.trim(),
        p_description: newCategoryDesc.trim() || null,
      });

      if (error) {
        if (error.message?.includes('does not exist') || error.code === '42883') {
          setFormError(
            'The secure create_category function is pending deployment in the database schema. Products can be added directly without a category.'
          );
        } else {
          setFormError(error.message);
        }
      } else if (data) {
        setNewCategoryName('');
        setNewCategoryDesc('');
        await fetchCatalog();
        if (data.category_id) setNewProductCategoryId(data.category_id);
        setShowCategoryModal(false);
      }
    } catch (err: unknown) {
      setFormError(err instanceof Error ? err.message : 'Failed to create category');
    } finally {
      setFormSubmitting(false);
    }
  };

  const filteredProducts = products.filter((prod) => {
    const matchesSearch =
      prod.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (prod.barcode && prod.barcode.toLowerCase().includes(searchQuery.toLowerCase())) ||
      (prod.sku && prod.sku.toLowerCase().includes(searchQuery.toLowerCase()));

    const matchesCategory =
      selectedCategory === 'ALL' || prod.category_id === selectedCategory;

    return matchesSearch && matchesCategory;
  });

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-6">
      {/* Top Controls Bar */}
      <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-4">
        <div className="flex items-center gap-3 flex-1 max-w-md">
          <div className="relative flex-1">
            <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search by name, SKU, or barcode..."
              className="w-full pl-9 pr-4 py-2 bg-white border border-slate-200 rounded-xl text-xs text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500 transition-all shadow-sm"
            />
          </div>

          <div className="relative">
            <select
              value={selectedCategory}
              onChange={(e) => setSelectedCategory(e.target.value)}
              aria-label="Filter products by category"
              className="appearance-none pl-8 pr-7 py-2 bg-white border border-slate-200 rounded-xl text-xs font-medium text-slate-700 hover:border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-500 cursor-pointer shadow-sm transition-all"
            >
              <option value="ALL">All Categories</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
            <Filter className="w-3.5 h-3.5 text-slate-400 absolute left-2.5 top-1/2 -translate-y-1/2 pointer-events-none" />
          </div>
        </div>

        {isOrgAdmin && (
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => {
                setFormError(null);
                setShowCategoryModal(true);
              }}
              className="px-3.5 py-2 text-xs font-semibold text-slate-700 bg-white border border-slate-200 hover:bg-slate-50 rounded-xl shadow-sm transition-all flex items-center gap-1.5"
            >
              <FolderPlus className="w-3.5 h-3.5 text-slate-500" />
              New Category
            </button>

            <button
              type="button"
              onClick={() => {
                setFormError(null);
                setFormSuccess(null);
                setShowCreateModal(true);
              }}
              className="px-4 py-2 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl shadow-sm shadow-indigo-600/30 transition-all flex items-center gap-1.5"
            >
              <Plus className="w-4 h-4" />
              Add Product
            </button>
          </div>
        )}
      </div>

      {/* Product Catalog Table */}
      <div className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
        <div className="p-4 border-b border-slate-100 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Tag className="w-4 h-4 text-indigo-600" />
            <h3 className="text-sm font-bold text-slate-800">Master Product Catalog</h3>
          </div>
          <span className="text-xs font-medium text-slate-400">
            {filteredProducts.length} of {products.length} products
          </span>
        </div>

        {loading ? (
          <div className="p-12 text-center text-slate-400 text-xs">
            <div className="w-6 h-6 border-2 border-indigo-600/20 border-t-indigo-600 rounded-full animate-spin mx-auto mb-2"></div>
            Loading catalog...
          </div>
        ) : filteredProducts.length === 0 ? (
          <div className="p-12 text-center">
            <Package className="w-10 h-10 text-slate-300 mx-auto mb-3" />
            <p className="text-sm font-semibold text-slate-700">No products found</p>
            <p className="text-xs text-slate-400 mt-1 max-w-sm mx-auto">
              {searchQuery || selectedCategory !== 'ALL'
                ? 'Try adjusting your search criteria or category filter.'
                : 'Get started by creating your first catalog product.'}
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="bg-slate-50/70 border-b border-slate-100 text-[11px] font-semibold text-slate-500 uppercase tracking-wider">
                  <th className="py-3 px-5">Product Name</th>
                  <th className="py-3 px-4">Category</th>
                  <th className="py-3 px-4">Unit Type</th>
                  <th className="py-3 px-4">SKU / Barcode</th>
                  <th className="py-3 px-4 text-right">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 text-xs">
                {filteredProducts.map((prod) => (
                  <tr key={prod.id} className="hover:bg-slate-50/60 transition-colors">
                    <td className="py-3.5 px-5">
                      <div className="font-semibold text-slate-900">{prod.name}</div>
                      {prod.description && (
                        <div className="text-[11px] text-slate-400 truncate max-w-xs">
                          {prod.description}
                        </div>
                      )}
                    </td>
                    <td className="py-3.5 px-4 text-slate-600">
                      {prod.category?.name ? (
                        <span className="px-2 py-0.5 bg-slate-100 text-slate-700 rounded text-[11px] font-medium">
                          {prod.category.name}
                        </span>
                      ) : (
                        <span className="text-slate-400 italic">Uncategorized</span>
                      )}
                    </td>
                    <td className="py-3.5 px-4">
                      {prod.unit_type === 'PACKAGED' ? (
                        <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-blue-50 text-blue-700 border border-blue-200/60">
                          <Package className="w-3 h-3" /> Packaged
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200/60">
                          <Scale className="w-3 h-3" /> Loose (Weighed)
                        </span>
                      )}
                    </td>
                    <td className="py-3.5 px-4 font-mono text-slate-500">
                      {prod.barcode ? (
                        <div className="flex items-center gap-1">
                          <Barcode className="w-3 h-3 text-slate-400" />
                          <span>{prod.barcode}</span>
                        </div>
                      ) : prod.sku ? (
                        <span>{prod.sku}</span>
                      ) : (
                        <span className="text-slate-300">-</span>
                      )}
                    </td>
                    <td className="py-3.5 px-4 text-right">
                      {prod.is_active ? (
                        <span className="inline-flex items-center gap-1 text-[11px] font-medium text-emerald-600">
                          <CheckCircle2 className="w-3 h-3" /> Active
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 text-[11px] font-medium text-slate-400">
                          <XCircle className="w-3 h-3" /> Inactive
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Modal: New Product */}
      {showCreateModal && (
        <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-lg w-full p-6 shadow-2xl border border-slate-200 animate-in fade-in zoom-in-95 duration-150">
            <h3 className="text-base font-bold text-slate-900 mb-1">Add Catalog Product</h3>
            <p className="text-xs text-slate-500 mb-5">
              Enrolls a master product definition across all shops in {activeOrg?.name}.
            </p>

            {formError && (
              <div className="mb-4 p-3 bg-rose-50 border border-rose-200 text-rose-700 rounded-xl text-xs flex items-start gap-2">
                <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                <span>{formError}</span>
              </div>
            )}

            {formSuccess && (
              <div className="mb-4 p-3 bg-emerald-50 border border-emerald-200 text-emerald-700 rounded-xl text-xs flex items-start gap-2">
                <CheckCircle2 className="w-4 h-4 flex-shrink-0 mt-0.5" />
                <span>{formSuccess}</span>
              </div>
            )}

            <form onSubmit={handleCreateProduct} className="space-y-4">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">Product Name *</label>
                <input
                  type="text"
                  required
                  value={newProductName}
                  onChange={(e) => setNewProductName(e.target.value)}
                  placeholder="e.g. Organic Brown Rice 1kg or Fuji Apples"
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">Category</label>
                  <select
                    value={newProductCategoryId}
                    onChange={(e) => setNewProductCategoryId(e.target.value)}
                    aria-label="Category for new product"
                    className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  >
                    <option value="">(No Category)</option>
                    {categories.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.name}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">Unit Type *</label>
                  <select
                    value={newProductUnitType}
                    onChange={(e) => setNewProductUnitType(e.target.value as UnitType)}
                    aria-label="Unit Type for new product"
                    className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  >
                    <option value="PACKAGED">PACKAGED (Integer units)</option>
                    <option value="LOOSE">LOOSE (Weighed via IoT Scale)</option>
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">Barcode</label>
                  <input
                    type="text"
                    value={newProductBarcode}
                    onChange={(e) => setNewProductBarcode(e.target.value)}
                    placeholder="EAN-13 / UPC"
                    className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">SKU</label>
                  <input
                    type="text"
                    value={newProductSku}
                    onChange={(e) => setNewProductSku(e.target.value)}
                    placeholder="e.g. RICE-BRN-01"
                    className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">Description</label>
                <textarea
                  rows={2}
                  value={newProductDescription}
                  onChange={(e) => setNewProductDescription(e.target.value)}
                  placeholder="Optional details, supplier specs, or notes..."
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setShowCreateModal(false)}
                  className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={formSubmitting}
                  className="px-4 py-2 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl transition-all disabled:opacity-50 flex items-center gap-1.5"
                >
                  {formSubmitting ? 'Enrolling...' : 'Save Product'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal: New Category */}
      {showCategoryModal && (
        <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-sm w-full p-6 shadow-2xl border border-slate-200">
            <h3 className="text-base font-bold text-slate-900 mb-1">Create Category</h3>
            <p className="text-xs text-slate-500 mb-4">Organize catalog products into groups.</p>

            <form onSubmit={handleCreateCategory} className="space-y-3">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">Category Name *</label>
                <input
                  type="text"
                  required
                  value={newCategoryName}
                  onChange={(e) => setNewCategoryName(e.target.value)}
                  placeholder="e.g. Dairy, Produce, Bakery"
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">Description</label>
                <input
                  type="text"
                  value={newCategoryDesc}
                  onChange={(e) => setNewCategoryDesc(e.target.value)}
                  placeholder="Optional summary..."
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setShowCategoryModal(false)}
                  className="px-3.5 py-1.5 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={formSubmitting}
                  className="px-3.5 py-1.5 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl"
                >
                  Create
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
